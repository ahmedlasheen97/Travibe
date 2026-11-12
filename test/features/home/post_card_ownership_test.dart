import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/post_card.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';
import 'package:travibe/features/follow/widgets/follow_action_builder.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import '../profile/fixtures.dart' as fixture;

class _Follows extends FollowRepo {
  final requests = <String>[];
  Completer<PublicUserModel>? pending;
  @override
  Future<PublicUserModel> setFollowing(String id, bool following) async {
    requests.add(id);
    return pending?.future ??
        PublicUserModel.fromJson({
          'id': int.parse(id),
          'name': 'Same Name',
          'is_following': following,
        });
  }
}

void main() {
  late fixture.MemoryProfileRepo profiles;
  late CurrentUserCubit current;
  late _Follows repo;
  late FollowCubit follow;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('account-7');
    profiles = fixture.MemoryProfileRepo()
      ..result = fixture.profile(name: 'Same Name');
    current = CurrentUserCubit(profileRepo: profiles);
    repo = _Follows();
    follow = FollowCubit(repo: repo);
  });
  tearDown(() async {
    await current.close();
    await follow.close();
    await PreferencesManager().clear();
  });

  Widget card(
    Object? author, {
    bool following = false,
    Object? fallback,
    int? revision,
    VoidCallback? more,
  }) => FollowActionBuilder(
    userId: author?.toString() ?? '',
    initialFollowing: following,
    builder: (_, following, pending, toggle) => PostCard(
      authorId: author,
      currentUserId: fallback,
      currentUserSessionRevision: revision,
      postId: '1',
      name: 'Same Name',
      avatar: null,
      time: 'now',
      text: 'Caption',
      likes: '0',
      comments: '0',
      showFollowButton: true,
      isFollowing: following,
      isFollowPending: pending,
      onFollowTap: toggle,
      onMoreTap: more,
    ),
  );
  Future<void> show(
    WidgetTester tester,
    Widget child, {
    bool load = true,
    bool shared = true,
  }) async {
    if (load && current.state.profile == null) await current.load();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: follow),
              if (shared) BlocProvider.value(value: current),
            ],
            child: Scaffold(body: child),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void noAction() {
    expect(find.text('Follow'), findsNothing);
    expect(find.text('Following'), findsNothing);
    expect(find.text('Updating…'), findsNothing);
  }

  InkWell followInk(WidgetTester tester) => tester.widget<InkWell>(
    find
        .ancestor(of: find.text('Follow'), matching: find.byType(InkWell))
        .first,
  );

  for (final author in <Object>[7, '7', ' 007 ']) {
    for (final following in [false, true]) {
      testWidgets(
        'own stable ID $author hides ${following ? 'Following' : 'Follow'} without a placeholder',
        (tester) async {
          var options = 0;
          await show(
            tester,
            card(author, following: following, more: () => options++),
          );
          noAction();
          expect(find.text('Same Name'), findsOneWidget);
          expect(find.text('now'), findsOneWidget);
          expect(find.byType(CircleAvatar), findsOneWidget);
          // The name slot (not just the text link) reaches ⋮: no Follow gap.
          final nameBox = find
              .ancestor(
                of: find.text('Same Name'),
                matching: find.byType(Align),
              )
              .first;
          final more = find
              .ancestor(
                of: find.byIcon(Icons.more_vert),
                matching: find.byType(InkWell),
              )
              .first;
          expect(
            tester.getRect(nameBox).right,
            closeTo(tester.getRect(more).left, .01),
          );
          await tester.tap(more);
          await tester.pump();
          expect(options, 1);
          expect(repo.requests, isEmpty);
          expect(profiles.reads, hasLength(1));
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'another author with the same display name retains follow/pending/unfollow',
    (tester) async {
      repo.pending = Completer<PublicUserModel>();
      await show(tester, card('8'));
      await tester.tap(find.text('Follow'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Updating…'), findsOneWidget);
      expect(repo.requests, ['8']);
      repo.pending!.complete(
        PublicUserModel.fromJson({'id': 8, 'is_following': true}),
      );
      await tester.pumpAndSettle();
      expect(find.text('Following'), findsOneWidget);
      repo.pending = null;
      await tester.tap(find.text('Following'));
      await tester.pumpAndSettle();
      expect(find.text('Follow'), findsOneWidget);
      expect(repo.requests, ['8', '8']);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'identity loading never flashes own Follow, and missing identity is not treated as owned',
    (tester) async {
      profiles.hold = true;
      final request = current.load();
      await show(tester, card('7'), load: false);
      noAction();
      profiles.reads.single.result.complete(fixture.profile(id: 7));
      await request;
      await tester.pumpAndSettle();
      noAction();
      await show(tester, card('8'));
      expect(find.text('Follow'), findsOneWidget);
      expect(repo.requests, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'another post waits for confirmed identity, then becomes actionable',
    (tester) async {
      profiles.hold = true;
      final request = current.load();
      await show(tester, card('8'), load: false);
      noAction();
      profiles.reads.single.result.complete(fixture.profile(id: 7));
      await request;
      await tester.pumpAndSettle();
      expect(find.text('Follow'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'account switch clears old identity and retained follow callbacks cannot follow self',
    (tester) async {
      await show(tester, card('8'));
      final oldTap = followInk(tester).onTap!;
      profiles.hold = true;
      await PreferencesManager().saveToken('account-8');
      oldTap();
      expect(repo.requests, isEmpty);
      await tester.pumpAndSettle();
      noAction();
      profiles.reads.last.result.complete(fixture.profile(id: 8));
      await tester.pumpAndSettle();
      noAction();
      oldTap();
      expect(repo.requests, isEmpty);
      await PreferencesManager().saveToken('account-9');
      await tester.pumpAndSettle();
      noAction();
      profiles.reads.last.result.complete(fixture.profile(id: 9));
      await tester.pumpAndSettle();
      expect(find.text('Follow'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('logout hides the action and invalidates an earlier callback', (
    tester,
  ) async {
    await show(tester, card('8'));
    final oldTap = followInk(tester).onTap!;
    await PreferencesManager().clearSession();
    oldTap();
    await tester.pumpAndSettle();
    noAction();
    expect(repo.requests, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'an old /user response cannot restore ownership after a session switch',
    (tester) async {
      profiles.hold = true;
      final oldRequest = current.load();
      await show(tester, card('8'), load: false);
      final old = profiles.reads.single;
      await PreferencesManager().saveToken('account-8');
      final fresh = profiles.reads.last;
      old.result.complete(fixture.profile(id: 7));
      await oldRequest;
      await tester.pumpAndSettle();
      noAction();
      fresh.result.complete(fixture.profile(id: 8));
      await tester.pumpAndSettle();
      noAction();
      expect(repo.requests, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'session-bound Home identity is reused without another identity service or read',
    (tester) async {
      final revision = PreferencesManager().sessionRevision;
      await show(
        tester,
        card('7', fallback: 7, revision: revision),
        shared: false,
        load: false,
      );
      noAction();
      await show(
        tester,
        card('8', fallback: 7, revision: revision),
        shared: false,
        load: false,
      );
      expect(find.text('Follow'), findsOneWidget);
      expect(profiles.reads, isEmpty);
      await PreferencesManager().saveToken('account-8');
      await tester.pumpAndSettle();
      noAction();
      expect(profiles.reads, hasLength(1)); // Existing Cubit reloads on login.
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'missing/malformed author IDs never form a false own-ID comparison or invalid mutation',
    (tester) async {
      for (final id in ['', '0', 'null', '7.0', '-7']) {
        await show(tester, card(id));
        noAction();
      }
      await show(tester, card('8'));
      expect(find.text('Follow'), findsOneWidget);
      expect(repo.requests, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('block-pending restrictions on another author remain in effect', (
    tester,
  ) async {
    follow.setBlockPending('8', true);
    await show(tester, card('8'));
    expect(find.text('Follow'), findsOneWidget);
    expect(followInk(tester).onTap, isNull);
    expect(repo.requests, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
