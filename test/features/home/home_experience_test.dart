import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/home/widgets/home_loading_skeleton.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_users_cubit.dart';
import 'package:travibe/features/follow/screens/follow_users_screen.dart';
import 'package:travibe/features/home/screens/home_screen.dart';
import 'package:travibe/features/home/widgets/following_empty_state.dart';
import 'package:travibe/features/home/widgets/home_stories.dart';
import 'package:travibe/features/home/widgets/suggested_users_section.dart';
import 'package:travibe/features/home/widgets/suggested_user_card.dart';
import 'package:travibe/features/home/widgets/home_user_avatar.dart';
import 'package:travibe/features/home/data/posts_page_model.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/features/search/data/users_page_model.dart';
import 'home_experience_fixtures.dart';
import 'package:travibe/root.dart';

void main() {
  late AccountRepo account;
  late PeopleRepo people;
  late EmptyPostsRepo posts;
  late FollowCubit follow;
  late BlockCubit block;
  setUp(() {
    account = AccountRepo();
    people = PeopleRepo(account);
    posts = EmptyPostsRepo();
    follow = FollowCubit(repo: people);
    block = BlockCubit(follow: follow);
  });
  tearDown(() async {
    await block.close();
    await follow.close();
  });

  Future<void> show(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    Widget? child,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: follow),
                BlocProvider.value(value: block),
              ],
              child:
                  child ?? HomeScreen(accountRepo: account, postsRepo: posts),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> following(WidgetTester tester) async {
    await tester.tap(find.text('Following').first);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'zero relationship state keeps the existing illustration and opens discovery',
    (tester) async {
      await show(tester);
      await following(tester);
      expect(find.text('You don’t follow anyone yet.'), findsOneWidget);
      expect(find.byType(FollowingEmptyState), findsOneWidget);
      expect(find.byType(HomeStories), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(FollowingEmptyState),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Image &&
                widget.image is AssetImage &&
                (widget.image as AssetImage).assetName ==
                    'assets/images/home/image 50.png',
          ),
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Explore People'));
      await tester.tap(find.text('Explore People'));
      await tester.pumpAndSettle();
      expect(find.byType(FollowUsersScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('switching feed tabs reuses cached feeds without a refresh', (
    tester,
  ) async {
    await show(tester);
    await following(tester);
    await tester.tap(find.text('For You').first);
    await tester.pumpAndSettle();
    expect(posts.requests.map((r) => r.feed), [
      FeedType.explore,
      FeedType.following,
    ]);
    expect(posts.requests.every((r) => r.cursor == null), true);
    await tester.tap(find.text('For You').first);
    await tester.pumpAndSettle();
    expect(posts.requests, hasLength(2));
  });

  testWidgets('following people without posts gets a no-posts state', (
    tester,
  ) async {
    account.followingCount = 2;
    await show(tester);
    await following(tester);
    expect(find.byType(FollowingEmptyState), findsNothing);
    expect(find.text('No posts yet'), findsOneWidget);
    expect(
      find.text('New posts from people you follow will appear here.'),
      findsOneWidget,
    );
  });

  testWidgets('loading and API errors never show the zero-follow empty state', (
    tester,
  ) async {
    posts.followingGate = Completer<PostsPageModel>();
    await show(tester);
    await tester.tap(find.text('Following').first);
    await tester.pump();
    expect(find.byType(FollowingEmptyState), findsNothing);
    expect(find.byType(HomeFeedSkeleton), findsOneWidget);
    posts.followingGate!.completeError(ApiError(message: 'Feed failed'));
    await tester.pumpAndSettle();
    expect(find.text('Feed failed'), findsOneWidget);
    expect(find.byType(FollowingEmptyState), findsNothing);
    posts.followingGate = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(FollowingEmptyState), findsOneWidget);
  });

  testWidgets('confirmed follow and unfollow refresh the relationship count', (
    tester,
  ) async {
    await show(tester);
    await following(tester);
    await follow.toggle('2', currentlyFollowing: false);
    await tester.pumpAndSettle();
    expect(account.calls, 2);
    expect(find.byType(FollowingEmptyState), findsNothing);
    expect(find.text('No posts yet'), findsOneWidget);
    await follow.toggle('2', currentlyFollowing: true);
    await tester.pumpAndSettle();
    expect(account.calls, 3);
    expect(find.byType(FollowingEmptyState), findsOneWidget);
  });

  testWidgets('account request failure retries to confirmed zero following', (
    tester,
  ) async {
    account.error = ApiError(message: 'Unable to reach your account.');
    await show(tester);
    await following(tester);
    expect(find.text('Unable to reach your account.'), findsOneWidget);
    expect(find.byType(FollowingEmptyState), findsNothing);
    account.error = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(FollowingEmptyState), findsOneWidget);
    expect(find.text('Explore People'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'horizontal cards deduplicate and exclude self and See All opens discovery',
    (tester) async {
      people.suggestions = [
        suggested('1', name: 'Viewer'),
        suggested('2'),
        suggested('2'),
        suggested('3', name: 'Other'),
      ];
      await show(tester);
      await tester.ensureVisible(find.text('Suggested for You'));
      expect(find.byType(SuggestedUserCard), findsNWidgets(2));
      expect(find.text('0 followers'), findsNothing);
      expect(find.text('0 following'), findsNothing);
      expect(find.text('Block'), findsNothing);
      await tester.tap(find.text('See All'));
      await tester.pumpAndSettle();
      expect(find.byType(FollowUsersScreen), findsOneWidget);
    },
  );

  testWidgets(
    'cards keep Following visible and prevent duplicate pending follows',
    (tester) async {
      final list = FollowUsersCubit(repo: people)..load();
      addTearDown(list.close);
      await show(
        tester,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SuggestedUsersSection(
            compact: true,
            currentUserId: '1',
            cubit: list,
          ),
        ),
      );
      people.mutationGate = Completer();
      await tester.tap(find.text('Follow'));
      await tester.pump();
      await follow.toggle('2', currentlyFollowing: false);
      expect(people.mutations, 1);
      people.mutationGate!.complete(suggested('2').copyWith(isFollowing: true));
      await tester.pumpAndSettle();
      expect(find.byType(SuggestedUserCard), findsOneWidget);
      expect(find.text('Following'), findsOneWidget);
    },
  );

  testWidgets('long card labels and missing avatars fit a small viewport', (
    tester,
  ) async {
    people.suggestions = [
      suggested(
        '2',
        name: 'Very long display name ' * 5,
        username: 'long_username_' * 10,
      ),
    ];
    final list = FollowUsersCubit(repo: people)..load();
    addTearDown(list.close);
    await show(
      tester,
      size: const Size(320, 480),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SuggestedUsersSection(
          compact: true,
          currentUserId: '1',
          cubit: list,
        ),
      ),
    );
    expect(find.byType(HomeUserAvatar), findsOneWidget);
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    final name = tester.widget<Text>(find.text(people.suggestions.single.name));
    final handle = tester.widget<Text>(
      find.text(people.suggestions.single.handle),
    );
    expect(name.maxLines, 1);
    expect(name.overflow, TextOverflow.ellipsis);
    expect(handle.maxLines, 1);
    expect(handle.overflow, TextOverflow.ellipsis);
    expect(handle.data, startsWith('@'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('small Following screen scrolls to CTA without overflow', (
    tester,
  ) async {
    await show(tester, size: const Size(320, 480));
    await following(tester);
    await tester.ensureVisible(find.text('Explore People'));
    expect(find.text('You don’t follow anyone yet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'missing relationship count shows retry instead of a false empty state',
    (tester) async {
      account.followingCount = null;
      await show(tester);
      await following(tester);
      expect(find.byType(FollowingEmptyState), findsNothing);
      expect(
        find.text('Unable to load your following count. Please try again.'),
        findsOneWidget,
      );
    },
  );
  testWidgets('horizontal suggestions keep pagination and retry behavior', (
    tester,
  ) async {
    var calls = 0;
    var failNext = true;
    final list = FollowUsersCubit(
      loadPage: (page) async {
        calls++;
        if (page == 2 && failNext) {
          throw ApiError(message: 'More people failed');
        }
        return UsersPageModel(
          users: [suggested(page == 1 ? '2' : '3')],
          currentPage: page,
          lastPage: 2,
          total: 2,
        );
      },
    )..load();
    addTearDown(list.close);
    await show(
      tester,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SuggestedUsersSection(
          compact: true,
          currentUserId: '1',
          cubit: list,
        ),
      ),
    );
    await tester.tap(find.text('More people'));
    await tester.pumpAndSettle();
    expect(find.text('More people failed'), findsOneWidget);
    failNext = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(SuggestedUserCard), findsNWidgets(2));
    expect(calls, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Explore API failure offers retry rather than an empty feed', (
    tester,
  ) async {
    posts.error = ApiError(message: 'Network failed');
    await show(tester);
    expect(find.text('Network failed'), findsOneWidget);
    expect(find.text('No posts yet'), findsNothing);
    posts.error = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No posts yet'), findsOneWidget);
    expect(find.text('Suggested for You'), findsOneWidget);
  });
  testWidgets(
    'horizontal suggestions do not hide the Create Post navigation button',
    (tester) async {
      people.suggestions = [suggested('2'), suggested('3'), suggested('4')];
      await show(
        tester,
        child: Root(
          postsRepo: posts,
          homeAccountRepo: account,
          followRepo: people,
        ),
      );
      await tester.ensureVisible(find.text('Suggested for You'));
      // Show nav again after any vertical positioning performed by ensureVisible.
      final scroll = find.descendant(
        of: find.byType(SuggestedUsersSection),
        matching: find.byType(ListView),
      );
      final before = tester
          .widget<AnimatedSlide>(find.byType(AnimatedSlide))
          .offset;
      await tester.drag(scroll, const Offset(-100, 0));
      await tester.pumpAndSettle();
      expect(
        tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset,
        before,
      );
      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
