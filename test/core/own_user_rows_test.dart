import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/navigation/my_profile_tab.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/utils/formatters.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/comments/data/comment_model.dart';
import 'package:travibe/features/comments/widgets/comment_row.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/widgets/follow_pill.dart';
import 'package:travibe/features/follow/widgets/follow_user_tile.dart';
import 'package:travibe/features/follow_requests/cubit/incoming_requests_cubit.dart';
import 'package:travibe/features/follow_requests/screens/follow_requests_screen.dart';
import 'package:travibe/features/follow_requests/widgets/follow_request_actions.dart';
import 'package:travibe/features/home/widgets/suggested_user_card.dart';
import 'package:travibe/features/likes/widgets/liked_by_sheet.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/widgets/profile_stats.dart';
import 'package:travibe/features/search/widgets/person_result_tile.dart';
import 'package:travibe/features/stories/cubit/story_viewer_cubit.dart';
import 'package:travibe/features/stories/cubit/story_viewers_cubit.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/widgets/story_viewers_sheet.dart';

import '../features/likes/likers_fixtures.dart';
import '../features/profile/fixtures.dart' as profile;
import '../features/stories/story_owner_controls_test.dart'
    show OwnerRepo, viewersPage;
import '../features/stories/story_viewer_test.dart' show viewerDetail;

/// The signed-in user is 7 (profile fixture); 8 is someone else.
const me = 7, other = 8;

void main() {
  late FollowCubit follow;
  late BlockCubit blocks;
  late CurrentUserCubit current;
  late int profileTabOpens;
  final owner = Object();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('own-rows');
    follow = FollowCubit(repo: FollowWrites());
    blocks = BlockCubit(follow: follow);
    current = CurrentUserCubit(
      profileRepo: profile.MemoryProfileRepo()..result = profile.profile(),
    );
    await current.load();
    profileTabOpens = 0;
    MyProfileTab.attach(owner, () => profileTabOpens++);
  });
  tearDown(() async {
    MyProfileTab.detach(owner);
    await blocks.close();
    await follow.close();
    await current.close();
    await PreferencesManager().clear();
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
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
              BlocProvider.value(value: blocks),
              BlocProvider.value(value: current),
            ],
            child: Scaffold(body: child),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder inRow(Finder row, Finder target) =>
      find.descendant(of: row, matching: target);

  group('search results / followers / following (PersonResultTile)', () {
    testWidgets('my row has no Follow, "Follows you" or ⋮; tap → Profile tab', (
      tester,
    ) async {
      var otherTaps = 0;
      Widget tile(int id) => PersonResultTile(
        key: ValueKey('tile-$id'),
        user: liker(id),
        followsYou: true,
        onFollowTap: () {},
        onTap: () => otherTaps++,
        trailing: const Icon(Icons.more_vert, key: ValueKey('trailing')),
      );
      await pump(tester, Column(children: [tile(me), tile(other)]));
      final mine = find.byKey(const ValueKey('tile-$me'));
      final theirs = find.byKey(const ValueKey('tile-$other'));
      expect(inRow(mine, find.text('Follow')), findsNothing);
      expect(inRow(mine, find.text('Follows you')), findsNothing);
      expect(inRow(mine, find.byKey(const ValueKey('trailing'))), findsNothing);
      expect(inRow(theirs, find.text('Follow')), findsOneWidget);
      expect(inRow(theirs, find.text('Follows you')), findsOneWidget);
      expect(
        inRow(theirs, find.byKey(const ValueKey('trailing'))),
        findsOneWidget,
      );

      await tester.tap(mine);
      await tester.pump();
      expect(profileTabOpens, 1);
      expect(otherTaps, 0);
      await tester.tap(theirs);
      await tester.pump();
      expect(otherTaps, 1);
    });

    testWidgets('followers list row: no Follow or User options for me', (
      tester,
    ) async {
      await pump(
        tester,
        Column(
          children: [
            FollowUserTile(key: const ValueKey('f-$me'), user: liker(me)),
            FollowUserTile(key: const ValueKey('f-$other'), user: liker(other)),
          ],
        ),
      );
      final mine = find.byKey(const ValueKey('f-$me'));
      final theirs = find.byKey(const ValueKey('f-$other'));
      expect(inRow(mine, find.text('Follow')), findsNothing);
      expect(inRow(mine, find.byTooltip('User options')), findsNothing);
      expect(inRow(theirs, find.text('Follow')), findsOneWidget);
      // Their ⋮ menu counts are pluralized: "1 follower", not "1 followers".
      await tester.tap(inRow(theirs, find.byTooltip('User options')));
      await tester.pumpAndSettle();
      expect(find.text('1 follower'), findsOneWidget);
      expect(find.text('1 followers'), findsNothing);
    });
  });

  testWidgets('follow requests: my row has no Accept/Decline actions', (
    tester,
  ) async {
    final incoming = IncomingRequestsCubit(follow: follow);
    addTearDown(incoming.close);
    await pump(
      tester,
      BlocProvider.value(
        value: incoming,
        child: Column(
          children: [
            FollowRequestTile(key: const ValueKey('r-$me'), user: liker(me)),
            FollowRequestTile(
              key: const ValueKey('r-$other'),
              user: liker(other),
            ),
          ],
        ),
      ),
    );
    expect(
      inRow(
        find.byKey(const ValueKey('r-$me')),
        find.byType(FollowRequestActions),
      ),
      findsNothing,
    );
    expect(
      inRow(
        find.byKey(const ValueKey('r-$other')),
        find.byType(FollowRequestActions),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('r-$me')));
    await tester.pump();
    expect(profileTabOpens, 1);
  });

  testWidgets('Liked by: my row has no Follow or ⋮; tapping me → Profile tab', (
    tester,
  ) async {
    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => LikedBySheet.show(
            context,
            postId: 10,
            count: 2,
            repo: LikersRepo([
              [liker(me), liker(other)],
            ]),
          ),
          child: const Text('Open'),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final mine = find.byKey(const ValueKey('liker-$me'));
    final theirs = find.byKey(const ValueKey('liker-$other'));
    expect(inRow(mine, find.byType(FollowPill)), findsNothing);
    expect(inRow(mine, find.byTooltip('User options')), findsNothing);
    expect(inRow(theirs, find.byType(FollowPill)), findsOneWidget);
    await tester.tap(inRow(mine, find.text('User $me')));
    await tester.pump();
    expect(profileTabOpens, 1);
  });

  testWidgets('comments: tapping my own name opens the Profile tab', (
    tester,
  ) async {
    final comment = CommentModel.fromJson({
      'id': 1,
      'post_id': 10,
      'parent_id': null,
      'content': 'Mine',
      'permissions': {'can_edit': true, 'can_delete': true},
      'user': {'id': me, 'name': 'Me'},
    });
    await pump(
      tester,
      CommentRow(
        comment: comment,
        busy: false,
        expanded: false,
        onReply: () {},
        onToggleReplies: () {},
        onEdit: () {},
        onDelete: () {},
      ),
    );
    expect(find.text('Follow'), findsNothing);
    // Edit/Delete of my own comment stay available.
    expect(find.byTooltip('Comment options'), findsOneWidget);
    await tester.tap(find.text('Me'));
    await tester.pump();
    expect(profileTabOpens, 1);
  });

  testWidgets('suggested user card never offers Follow on myself', (
    tester,
  ) async {
    await pump(
      tester,
      Row(
        children: [
          SizedBox(
            height: 260,
            child: SuggestedUserCard(
              key: const ValueKey('s-$me'),
              user: liker(me),
            ),
          ),
          SizedBox(
            height: 260,
            child: SuggestedUserCard(
              key: const ValueKey('s-$other'),
              user: liker(other),
            ),
          ),
        ],
      ),
    );
    bool pillVisible(int id) => tester
        .widget<Visibility>(
          inRow(find.byKey(ValueKey('s-$id')), find.byType(Visibility)),
        )
        .visible;
    expect(pillVisible(me), isFalse);
    expect(pillVisible(other), isTrue);
  });

  group('story viewers', () {
    testWidgets('my own view is not listed; header says "1 View"', (
      tester,
    ) async {
      final repo = OwnerRepo()
        ..viewersHandler = (_) async =>
            StoryViewersPage.fromJson(viewersPage([me, other]));
      final cubit = StoryViewersCubit(
        storyId: 1,
        repo: repo,
        isOwner: () => true,
      );
      addTearDown(cubit.close);
      await cubit.refresh();
      await pump(
        tester,
        StoryViewersSheet(
          cubit: cubit,
          count: 1,
          follow: follow,
          blocks: blocks,
        ),
      );
      expect(find.text('Viewer $me'), findsNothing);
      expect(find.text('Viewer $other'), findsOneWidget);
      expect(find.byType(FollowPill), findsOneWidget);
      expect(find.byTooltip('Viewer options'), findsOneWidget);
      expect(find.text('1 View'), findsOneWidget);
      expect(find.text('1 Views'), findsNothing);
    });

    testWidgets('only me viewed: empty state, "0 Views"', (tester) async {
      final repo = OwnerRepo()
        ..viewersHandler = (_) async =>
            StoryViewersPage.fromJson(viewersPage([me]));
      final cubit = StoryViewersCubit(
        storyId: 1,
        repo: repo,
        isOwner: () => true,
      );
      addTearDown(cubit.close);
      await cubit.refresh();
      await pump(tester, StoryViewersSheet(cubit: cubit, count: 0));
      expect(find.text('No viewers yet.'), findsOneWidget);
      expect(find.text('0 Views'), findsOneWidget);
    });

    StoryDetail detail({
      required bool mine,
      required bool seen,
      required int views,
    }) => StoryDetail.fromJson(
      viewerDetail(1)
        ..['is_mine'] = mine
        ..['has_seen'] = seen
        ..['views_count'] = views,
    );

    test('my view is not counted on my own Story', () {
      // The server counted my own view row.
      expect(
        detail(mine: true, seen: true, views: 3).viewsCountExcludingOwner,
        2,
      );
      // I have no view row yet (or the backend stops recording it).
      expect(
        detail(mine: true, seen: false, views: 3).viewsCountExcludingOwner,
        3,
      );
      expect(
        detail(mine: true, seen: true, views: 0).viewsCountExcludingOwner,
        0,
      );
      // Someone else's Story is never adjusted.
      expect(
        detail(mine: false, seen: true, views: 3).viewsCountExcludingOwner,
        3,
      );
      final state = StoryViewerState(
        detail: detail(mine: true, seen: true, views: 5),
      );
      expect(state.visibleViewsCount, 4);
    });
  });

  group('pluralization', () {
    test('countLabel', () {
      expect(countLabel(1, 'View'), '1 View');
      expect(countLabel(2, 'View'), '2 Views');
      expect(countLabel(0, 'View'), '0 Views');
      expect(countLabel(1, 'follower'), '1 follower');
    });

    testWidgets('profile stats: "1 Post", "1 Follower"', (tester) async {
      await pump(
        tester,
        const ProfileStats(posts: 1, followers: 1, following: 1),
      );
      expect(find.text('Post'), findsOneWidget);
      expect(find.text('Follower'), findsOneWidget);
      expect(find.text('Following'), findsOneWidget);
      await pump(
        tester,
        const ProfileStats(posts: 2, followers: 0, following: 3),
      );
      expect(find.text('Posts'), findsOneWidget);
      expect(find.text('Followers'), findsOneWidget);
    });
  });
}
