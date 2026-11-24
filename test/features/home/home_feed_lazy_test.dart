import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/post_card.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/home/screens/home_screen.dart';
import 'package:travibe/features/likes/cubit/likes_cubit.dart';
import 'package:travibe/features/likes/data/like_model.dart';
import 'package:travibe/features/saved/cubit/saves_cubit.dart';

import 'home_experience_fixtures.dart' as fixture;
import 'home_responsive_ui_test.dart'
    show ResponsivePosts, ResponsiveSearch, ResponsiveStories;

/// Saving succeeds without the network.
class _Posts extends ResponsivePosts {
  @override
  Future<bool> setSaved(String postId, bool saved) async => saved;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('home-lazy-test');
  });
  tearDown(() => PreferencesManager().clear());

  testWidgets('liking or saving one Home post rebuilds only that card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Created inside the test's zone so their stream events flush on pump.
    final posts = _Posts();
    final account = fixture.AccountRepo()..followingCount = 2;
    final follow = FollowCubit(repo: fixture.PeopleRepo(account));
    final block = BlockCubit(follow: follow);
    final likes = LikesCubit();
    final saves = SavesCubit(repo: posts);
    addTearDown(() async {
      await saves.close();
      await likes.close();
      await block.close();
      await follow.close();
    });
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
                BlocProvider.value(value: likes),
                BlocProvider.value(value: saves),
              ],
              child: HomeScreen(
                postsRepo: posts,
                accountRepo: account,
                storiesRepo: ResponsiveStories(),
                searchRepo: ResponsiveSearch(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    PostCard card(int id) => tester.widget<PostCard>(
      find.descendant(
        of: find.byKey(ValueKey('home-post-$id')),
        matching: find.byType(PostCard),
      ),
    );
    // Lazy: the first page has 8 posts, but only those near the screen exist.
    expect(find.byType(PostCard).evaluate().length, lessThan(8));

    final first = card(1);
    final second = card(2);
    likes.accept({
      const LikeTarget.post(1): const LikeValue(isLiked: true, count: 7),
    }, requestRevision: likes.revision);
    await tester.pump();
    await tester.pump();
    expect(card(1).isLiked, isTrue);
    expect(card(1).likes, '7');
    expect(card(2), same(second));

    expect(first, isNot(same(card(1))));

    final liked = card(1);
    final page = await posts.getPosts();
    // The fixture post has no is_saved; give it a known state to toggle.
    final error = await saves.toggle(
      page.posts[1].copyWith(isSaved: false, hasSaveState: true),
    );
    expect(error, isNull);
    await tester.pump();
    await tester.pump();
    expect(card(2).isSaved, isTrue);
    expect(card(1), same(liked));
  });
}
