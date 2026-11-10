import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/block/data/block_repo.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'package:travibe/features/profile/screens/profile_screen.dart';
import 'package:travibe/features/profile/screens/edit_profile_screen.dart';
import 'fixtures.dart';

PublicUserModel publicUser(String id, {bool blocked = false}) =>
    PublicUserModel.fromJson({
      'id': int.parse(id),
      'name': 'Mona Hassan',
      'is_blocked': blocked,
      'is_following': true,
      'followers_count': 13,
      'following_count': 4,
    });

class ProfileBlocks extends BlockRepo {
  @override
  Future<PublicUserModel> setBlocked(String userId, bool blocked) async =>
      publicUser(userId, blocked: blocked);
}

class ProfileFollows extends FollowRepo {
  @override
  Future<PublicUserModel> setFollowing(String userId, bool following) async =>
      publicUser(userId);
}

void main() {
  late MemoryProfileRepo repo;
  setUp(() {
    repo = MemoryProfileRepo();
  });

  Future<void> show(
    WidgetTester tester, {
    int? userId,
    FollowCubit? follow,
    BlockCubit? block,
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final screen = ProfileScreen(
      userId: userId,
      profileRepo: repo,
      postsRepo: EmptyProfilePostsRepo(),
    );
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: follow == null
              ? screen
              : MultiBlocProvider(
                  providers: [
                    BlocProvider.value(value: follow),
                    BlocProvider.value(value: block!),
                  ],
                  child: screen,
                ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets(
    'own profile shows real account/about data and no sample content',
    (tester) async {
      await show(tester);
      expect(repo.reads.single.userId, isNull);
      expect(find.text('Mona Hassan'), findsOneWidget);
      expect(find.text('@mona'), findsOneWidget);
      expect(find.text('Salma Ali'), findsNothing);
      expect(find.text('Novotel Cairo El Borg'), findsNothing);
      expect(find.text('No posts yet'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Edit Profile'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('About'));
      await tester.pumpAndSettle();
      expect(find.text('العربية'), findsOneWidget);
      expect(find.text('Photography'), findsOneWidget);
    },
  );

  testWidgets(
    'owner edit navigation prefills current profile and public self remains read-only',
    (tester) async {
      await show(tester);
      await tester.tap(find.text('Edit Profile'));
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('full_name')))
            .controller!
            .text,
        'Mona Hassan',
      );
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      repo.result = ProfileModel.fromJson({...profileJson(), 'is_me': true});
      await show(tester, userId: 7);
      expect(find.text('Edit Profile'), findsNothing);
    },
  );

  testWidgets(
    'public mode hides owner controls and Saved without inferring a block',
    (tester) async {
      repo.result = ProfileModel.fromJson({
        ...profileJson(id: 23),
        'is_me': false,
      });
      await show(tester, userId: 23);
      expect(repo.reads.single.userId, 23);
      expect(find.text('Mona Hassan'), findsOneWidget);
      expect(find.text('Edit Profile'), findsNothing);
      expect(find.text('Saved'), findsNothing);
      expect(find.text('This profile is unavailable.'), findsNothing);
    },
  );

  testWidgets(
    'public data:null has a retryable unavailable view, not an empty profile',
    (tester) async {
      repo.result = null;
      await show(tester, userId: 23);
      expect(find.text('This profile is unavailable.'), findsOneWidget);
      expect(find.text('Edit Profile'), findsNothing);
      repo.result = profile(id: 23);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Mona Hassan'), findsOneWidget);
    },
  );

  testWidgets(
    'authentication error retries and pull-to-refresh fetches actual data',
    (tester) async {
      repo.error = ApiError(message: 'Session expired', statusCode: 401);
      await show(tester);
      expect(find.text('Session expired'), findsOneWidget);
      repo.error = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      repo.result = profile(name: 'Fresh profile');
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 350));
      await tester.pumpAndSettle();
      expect(find.text('Fresh profile'), findsOneWidget);
      expect(repo.reads, hasLength(3));
    },
  );

  testWidgets('unknown counts display a dash rather than a fabricated zero', (
    tester,
  ) async {
    repo.result = ProfileModel.fromJson({'id': 7});
    await show(tester);
    expect(find.text('—'), findsNWidgets(3));
    expect(find.text('0'), findsNothing);
  });

  testWidgets('disposing while loading ignores the late response', (
    tester,
  ) async {
    repo.hold = true;
    await show(tester, settle: false);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.reads.single.result.complete(profile());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'confirmed Follow mutation refreshes Profile using the existing Cubit',
    (tester) async {
      final follow = FollowCubit(repo: ProfileFollows());
      final block = BlockCubit(follow: follow, repo: ProfileBlocks());
      addTearDown(follow.close);
      addTearDown(block.close);
      await show(tester, follow: follow, block: block);
      repo.result = ProfileModel.fromJson({
        ...profileJson(),
        'following_count': 5,
      });
      await tester.runAsync(
        () => follow.toggle('23', currentlyFollowing: false),
      );
      await tester.pumpAndSettle();
      expect(repo.reads, hasLength(2));
      expect(find.text('5'), findsNWidgets(2));
    },
  );

  testWidgets(
    'confirmed block hides a public profile and invalidates an older request',
    (tester) async {
      final follow = FollowCubit();
      final block = BlockCubit(follow: follow, repo: ProfileBlocks());
      addTearDown(follow.close);
      addTearDown(block.close);
      repo.hold = true;
      await show(
        tester,
        userId: 23,
        follow: follow,
        block: block,
        settle: false,
      );
      await tester.runAsync(() => block.setBlocked('23', true));
      await tester.pumpAndSettle();
      expect(find.text('This profile is unavailable.'), findsOneWidget);
      repo.reads.first.result.complete(profile(id: 23));
      await tester.pumpAndSettle();
      expect(find.text('Mona Hassan'), findsNothing);
      repo.hold = false;
      repo.result = profile(id: 23);
      await tester.runAsync(() => block.setBlocked('23', false));
      await tester.pumpAndSettle();
      expect(find.text('Mona Hassan'), findsOneWidget);
    },
  );

  testWidgets('public navigation preserves existing session controllers', (
    tester,
  ) async {
    final follow = FollowCubit();
    final block = BlockCubit(follow: follow, repo: ProfileBlocks());
    addTearDown(follow.close);
    addTearDown(block.close);
    repo.result = profile(id: 23);
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
              BlocProvider.value(value: block),
            ],
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => ProfileScreen.open(
                    context,
                    userId: 23,
                    profileRepo: repo,
                    postsRepo: EmptyProfilePostsRepo(),
                  ),
                  child: const Text('Open profile'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open profile'));
    await tester.pumpAndSettle();
    expect(find.text('Mona Hassan'), findsOneWidget);
    await tester.runAsync(() => block.setBlocked('23', true));
    await tester.pumpAndSettle();
    expect(find.text('This profile is unavailable.'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(follow.isClosed, false);
    expect(block.isClosed, false);
  });

  testWidgets(
    'changing profile target disposes the old loader and ignores its response',
    (tester) async {
      repo.hold = true;
      Widget app(int id) => ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: ProfileScreen(
            userId: id,
            profileRepo: repo,
            postsRepo: EmptyProfilePostsRepo(),
          ),
        ),
      );
      await tester.pumpWidget(app(23));
      await tester.pump();
      await tester.pumpWidget(app(24));
      await tester.pump();
      expect(repo.reads.map((read) => read.userId), [23, 24]);
      repo.reads.last.result.complete(profile(id: 24, name: 'New target'));
      await tester.pumpAndSettle();
      repo.reads.first.result.complete(profile(id: 23, name: 'Old target'));
      await tester.pumpAndSettle();
      expect(find.text('New target'), findsOneWidget);
      expect(find.text('Old target'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
