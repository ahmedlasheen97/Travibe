import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/home/data/home_account_repo.dart';
import 'package:travibe/features/home/data/posts_page_model.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/features/home/screens/home_screen.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import '../../helpers/cursor_fixtures.dart';
import '../profile/fixtures.dart' as profile;
import 'home_experience_fixtures.dart' as home;

class _Account extends HomeAccountRepo {
  @override
  Future<HomeAccount> getAccount() async =>
      const HomeAccount(id: '7', name: 'Viewer', followingCount: 3);
}

class _Stories extends StoriesRepo {
  @override
  Future<StoriesPage> getStories({int page = 1}) async => StoriesPage.fromJson({
    'data': [],
    'meta': {'current_page': 1, 'last_page': 1, 'per_page': 15, 'total': 0},
    'links': {'next': null},
  });
}

class _Posts extends PostsRepo {
  bool published = false;
  final reads = <FeedType>[];
  @override
  Future<PostsPageModel> getPosts({
    FeedType feed = FeedType.explore,
    String? cursor,
    int perPage = 15,
  }) async {
    reads.add(feed);
    return PostsPageModel.fromCursorJson(
      cursorEnvelope(
        data: [
          for (final id in [if (published) 102, 101, 108])
            {
              'id': id,
              'user_id': id == 108 ? 8 : 7,
              'user': {
                'id': id == 108 ? 8 : 7,
                'name': id == 108 ? 'Another author' : 'Viewer',
                'is_following': false,
              },
              'content': 'Post $id',
            },
        ],
      ),
    );
  }
}

void main() {
  testWidgets(
    'own cards hide Follow immediately after publication, refresh and in both feeds',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await PreferencesManager().init();
      await PreferencesManager().saveToken('home-owner-7');
      final profiles = profile.MemoryProfileRepo();
      final current = CurrentUserCubit(profileRepo: profiles);
      await current.load();
      final account = home.AccountRepo();
      final people = home.PeopleRepo(account);
      final follow = FollowCubit(repo: people);
      final blocks = BlockCubit(follow: follow);
      final posts = _Posts();
      final publication = ValueNotifier(0);
      tester.view.physicalSize = const Size(390, 844);
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
                  BlocProvider.value(value: current),
                  BlocProvider.value(value: follow),
                  BlocProvider.value(value: blocks),
                ],
                child: HomeScreen(
                  postsRepo: posts,
                  accountRepo: _Account(),
                  storiesRepo: _Stories(),
                  publicationSignal: publication,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      void checkOwn(int id) {
        final scope = find.byKey(ValueKey('home-post-$id'));
        expect(scope, findsOneWidget);
        expect(
          find.descendant(of: scope, matching: find.text('Follow')),
          findsNothing,
        );
        expect(
          find.descendant(of: scope, matching: find.text('Following')),
          findsNothing,
        );
      }

      checkOwn(101);
      final other = find.byKey(const ValueKey('home-post-108'));
      expect(
        find.descendant(of: other, matching: find.text('Follow')),
        findsOneWidget,
      );
      posts.published = true;
      publication.value++;
      for (var i = 0; i < 4; i++) {
        await tester.pump();
        if (find.byKey(const ValueKey('home-post-102')).evaluate().isNotEmpty) {
          checkOwn(102);
        }
      }
      await tester.pumpAndSettle();
      checkOwn(102);
      expect(posts.reads, hasLength(3));
      expect(
        posts.reads.where((feed) => feed == FeedType.explore),
        hasLength(2),
      );
      expect(
        posts.reads.where((feed) => feed == FeedType.following),
        hasLength(1),
      );
      final refresh = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await refresh;
      await tester.pumpAndSettle();
      checkOwn(102);
      checkOwn(101);
      await tester.tap(find.text('Following').first);
      await tester.pumpAndSettle();
      checkOwn(102);
      checkOwn(101);
      final reads = posts.reads.length;
      await tester.tap(find.text('For You'));
      await tester.pumpAndSettle();
      checkOwn(102);
      expect(posts.reads, hasLength(reads));
      expect(people.mutations, 0);
      expect(profiles.reads, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      publication.dispose();
      await blocks.close();
      await follow.close();
      await current.close();
      await PreferencesManager().clear();
    },
  );
}
