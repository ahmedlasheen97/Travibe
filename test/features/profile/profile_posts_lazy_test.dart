import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/widgets/post_card.dart';
import 'package:travibe/features/home/cubit/post_activity_cubit.dart';
import 'package:travibe/features/home/cubit/posts_cubit.dart';
import 'package:travibe/features/likes/cubit/likes_cubit.dart';
import 'package:travibe/features/likes/data/like_model.dart';
import 'package:travibe/features/profile/widgets/profile_posts_sliver.dart';
import 'package:travibe/features/saved/cubit/saves_cubit.dart';

import '../../helpers/screen_util.dart';
import 'profile_posts_fixtures.dart';

void main() {
  late AuthorPostsRepo repo;
  late LikesCubit likes;
  late SavesCubit saves;
  late PostActivityCubit activity;
  late PostsCubit posts;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('profile-lazy-test');
  });
  tearDown(() => PreferencesManager().clear());

  Future<void> show(WidgetTester tester) async {
    // Created inside the test's zone so their stream events flush on pump.
    repo = AuthorPostsRepo()..authors = {7: List.generate(20, (i) => i + 1)};
    likes = LikesCubit();
    saves = SavesCubit(repo: repo);
    activity = PostActivityCubit();
    posts = PostsCubit(
      postsRepo: repo,
      userId: 7,
      likes: likes,
      saves: saves,
      activity: activity,
    );
    addTearDown(() async {
      await posts.close();
      await activity.close();
      await saves.close();
      await likes.close();
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      withScreenUtil(
        MaterialApp(
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: likes),
                BlocProvider.value(value: saves),
                BlocProvider.value(value: activity),
                BlocProvider.value(value: posts),
              ],
              child: const CustomScrollView(
                slivers: [ProfilePostsSliver(owner: true)],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  PostCard card(WidgetTester tester, int id) => tester.widget<PostCard>(
    find.descendant(
      of: find.byKey(ValueKey('profile-post-$id')),
      matching: find.byType(PostCard),
    ),
  );

  testWidgets('only the cards on screen are built', (tester) async {
    await show(tester);
    final built = find.byType(PostCard).evaluate().length;
    expect(built, greaterThan(0));
    expect(built, lessThan(20));
    expect(find.byKey(const ValueKey('profile-post-20')), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('profile-post-20')),
      400,
    );
    expect(find.byKey(const ValueKey('profile-post-20')), findsOneWidget);
  });

  testWidgets('liking one post rebuilds only that card', (tester) async {
    await show(tester);
    final first = card(tester, 1);
    final second = card(tester, 2);
    likes.accept({
      const LikeTarget.post(1): const LikeValue(isLiked: true, count: 99),
    }, requestRevision: likes.revision);
    await tester.pump();
    await tester.pump();
    expect(card(tester, 1), isNot(same(first)));
    expect(card(tester, 1).isLiked, isTrue);
    expect(card(tester, 1).likes, '99');
    // Post 2 kept the very same widget: it wasn't rebuilt.
    expect(card(tester, 2), same(second));
  });

  testWidgets('a comment count change rebuilds only that card', (tester) async {
    await show(tester);
    final first = card(tester, 1);
    final second = card(tester, 2);
    activity.setCommentsCount('2', 42);
    await tester.pump();
    await tester.pump();
    expect(card(tester, 2), isNot(same(second)));
    expect(card(tester, 1), same(first));
  });
}
