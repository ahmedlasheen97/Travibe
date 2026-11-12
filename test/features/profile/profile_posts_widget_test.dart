import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fixtures.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/post_card.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/home/cubit/post_activity_cubit.dart';
import 'package:travibe/features/home/cubit/posts_cubit.dart';
import 'package:travibe/features/likes/cubit/likes_cubit.dart';
import 'package:travibe/features/likes/data/like_model.dart';
import 'package:travibe/features/saved/cubit/saves_cubit.dart';
import 'package:travibe/features/profile/screens/profile_screen.dart';
import 'profile_posts_fixtures.dart';

class ProfileBlocks extends BlockCubit {
  ProfileBlocks({required super.follow});
  void confirm(String id, bool blocked) =>
      emit(BlockState(blocked: {id: blocked}));
}

void main() {
  late AuthorPostsRepo repo;
  late AuthorProfilesRepo profiles;
  late SavesCubit saves;
  late PostActivityCubit activity;
  late LikesCubit likes;
  late FollowCubit follow;
  late ProfileBlocks blocks;
  bool created = false;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('profile-posts-owner');
    repo = AuthorPostsRepo();
    profiles = AuthorProfilesRepo();
    created = false;
  });
  tearDown(() async {
    if (created) {
      await saves.close();
      await activity.close();
      await likes.close();
      await blocks.close();
      await follow.close();
    }
  });
  Future<void> show(
    WidgetTester tester, {
    int? userId,
    bool settle = true,
  }) async {
    if (!created) {
      saves = SavesCubit(repo: repo);
      activity = PostActivityCubit();
      likes = LikesCubit();
      follow = FollowCubit();
      blocks = ProfileBlocks(follow: follow);
      created = true;
    }
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
              BlocProvider.value(value: saves),
              BlocProvider.value(value: activity),
              BlocProvider.value(value: likes),
              BlocProvider<FollowCubit>.value(value: follow),
              BlocProvider<BlockCubit>.value(value: blocks),
            ],
            child: ProfileScreen(
              userId: userId,
              profileRepo: profiles,
              postsRepo: repo,
            ),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
  }

  testWidgets(
    'owner loads actual author posts from the authenticated profile ID',
    (tester) async {
      await show(tester);
      expect(repo.authorReads.single.userId, 7);
      expect(find.text('Owner 7'), findsOneWidget);
      expect(find.text('Author 7 post 101'), findsOneWidget);
      final ownCard = find.byType(PostCard).first;
      expect(tester.widget<PostCard>(ownCard).authorId, '7');
      expect(
        find.descendant(of: ownCard, matching: find.text('Follow')),
        findsNothing,
      );
      expect(
        find.descendant(of: ownCard, matching: find.text('Following')),
        findsNothing,
      );
      expect(find.text('Posts are not loaded yet.'), findsNothing);
      expect(find.text('Edit Profile'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
      final before = repo.authorReads.length;
      await tester.tap(find.text('About'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Posts').first);
      await tester.pumpAndSettle();
      expect(repo.authorReads.length, before);
    },
  );
  testWidgets(
    'public profile uses selected author ID and never exposes Saved or Edit',
    (tester) async {
      await show(tester, userId: 23);
      expect(repo.authorReads.single.userId, 23);
      expect(find.text('Public 23'), findsOneWidget);
      expect(find.text('Author 23 post 201'), findsOneWidget);
      expect(find.text('Saved'), findsNothing);
      expect(find.text('Edit Profile'), findsNothing);
    },
  );
  testWidgets(
    'public profile posts never show Follow; header state is shared app-wide',
    (tester) async {
      // Header says Following while the posts endpoint's author flag is stale.
      profiles = _FollowingProfiles();
      await show(tester, userId: 23);
      expect(find.widgetWithText(FilledButton, 'Following'), findsOneWidget);
      expect(find.byType(PostCard), findsWidgets);
      for (final card in tester.widgetList<PostCard>(find.byType(PostCard))) {
        expect(card.showFollowButton, isFalse);
      }
      for (final label in ['Follow', 'Following']) {
        expect(
          find.descendant(
            of: find.byType(PostCard),
            matching: find.text(label),
          ),
          findsNothing,
          reason: label,
        );
      }
      // Seeded for Home/Post cards, without counting as a follow mutation.
      expect(follow.state.following['23'], isTrue);
      expect(follow.state.followsYou['23'], isTrue);
      expect(follow.state.revision, 0);
      expect(repo.authorReads, hasLength(1));
    },
  );
  testWidgets('switching public profiles discards stale author responses', (
    tester,
  ) async {
    repo.holdAuthors = true;
    await show(tester, userId: 23, settle: false);
    expect(repo.authorReads.single.userId, 23);
    await show(tester, userId: 42, settle: false);
    expect(repo.authorReads.last.userId, 42);
    repo.authorReads.last.result.complete(authorPage(42, [301]));
    await tester.pumpAndSettle();
    repo.authorReads.first.result.complete(authorPage(23, [201]));
    await tester.pumpAndSettle();
    expect(find.text('Author 42 post 301'), findsOneWidget);
    expect(find.text('Author 23 post 201'), findsNothing);
  });
  testWidgets(
    'unavailable profiles never request posts; blocking invalidates pending author rows',
    (tester) async {
      profiles.unavailable = {23};
      await show(tester, userId: 23);
      expect(repo.authorReads, isEmpty);
      expect(find.text('This profile is unavailable.'), findsOneWidget);
      profiles.unavailable = {};
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(repo.authorReads, hasLength(1));
      repo.holdAuthors = true;
      final posts = tester.element(find.byType(PostCard)).read<PostsCubit>();
      final pending = posts.refresh();
      await tester.pump();
      blocks.confirm('23', true);
      await tester.pumpAndSettle();
      expect(find.byType(PostCard), findsNothing);
      repo.authorReads.last.result.complete(authorPage(23, [201]));
      await pending;
      await tester.pumpAndSettle();
      expect(find.byType(PostCard), findsNothing);
      expect(find.text('This profile is unavailable.'), findsOneWidget);
      repo.holdAuthors = false;
      blocks.confirm('23', false);
      await tester.pumpAndSettle();
      expect(find.text('Author 23 post 201'), findsOneWidget);
    },
  );
  testWidgets(
    'author failure retries, paginates and pull-refreshes independently',
    (tester) async {
      repo.authorError = ApiError(message: 'Author offline');
      await show(tester);
      await tester.scrollUntilVisible(
        find.text('Retry'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Author offline'), findsOneWidget);
      repo.authorError = null;
      repo.authorLast = 2;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Load more'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      repo.authors[7] = [102];
      repo.authorLast = 2;
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(repo.authorReads.last.page, 2);
      expect(find.text('Author 7 post 102'), findsOneWidget);
      repo.authorLast = 1;
      repo.authors[7] = [];
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 1000));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 1000));
      await tester.pumpAndSettle();
      expect(find.text('No posts yet'), findsOneWidget);
      expect(repo.authorReads.last.page, 1);
    },
  );
  testWidgets(
    'creation refreshes matching owner only and shares confirmed interaction state',
    (tester) async {
      await show(tester);
      repo.authors[7] = [102];
      activity.published(authorPost(102, 7));
      await tester.pumpAndSettle();
      expect(find.text('Author 7 post 102'), findsOneWidget);
      expect(repo.authorReads, hasLength(2));
      activity.published(authorPost(300, 42));
      await tester.pumpAndSettle();
      expect(repo.authorReads, hasLength(2));
      likes.accept({
        const LikeTarget.post(102): const LikeValue(isLiked: true, count: 12),
      }, requestRevision: likes.revision);
      activity.setCommentsCount('102', 9);
      await tester.pumpAndSettle();
      expect(tester.widget<PostCard>(find.byType(PostCard)).isLiked, true);
      expect(find.text('12'), findsWidgets);
      expect(find.text('9'), findsWidgets);
    },
  );
  testWidgets(
    'session switch reloads owner identity before fetching the new author',
    (tester) async {
      await show(tester);
      expect(find.text('Author 7 post 101'), findsOneWidget);
      profiles.ownId = 42;
      await tester.runAsync(
        () => PreferencesManager().saveToken('different-account'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Author 7 post 101'), findsNothing);
      expect(find.text('Author 42 post 301'), findsOneWidget);
      expect(repo.authorReads.last.userId, 42);
    },
  );
  testWidgets(
    'shared bookmark mutation from Profile is confirmed and reusable in Saved',
    (tester) async {
      await show(tester);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('post-save')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('post-save')));
      await tester.pumpAndSettle();
      expect(saves.state.values['101'], true);
      expect(tester.widget<PostCard>(find.byType(PostCard)).isSaved, true);
      expect(repo.writes.single.id, '101');
    },
  );
}

class _FollowingProfiles extends AuthorProfilesRepo {
  @override
  Future<ProfileModel?> getPublicProfile(int userId) async =>
      ProfileModel.fromJson({
        ...profileJson(id: userId, name: 'Public $userId'),
        'is_me': false,
        'is_following': true,
        'follows_you': true,
      });
}
