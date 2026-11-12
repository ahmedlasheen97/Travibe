import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:travibe/core/widgets/more_options_button.dart';
import 'package:travibe/core/widgets/post_card.dart';
import 'package:travibe/features/comments/screens/comments_screen.dart';
import 'package:travibe/features/home/cubit/hidden_posts_cubit.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/features/home/widgets/post_options_sheet.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/home/screens/post_screen.dart';
import 'package:travibe/features/likes/cubit/likes_cubit.dart';
import 'package:travibe/features/likes/widgets/liked_by_sheet.dart';
import '../comments/fixtures.dart';
import '../likes/fixtures.dart';
import '../likes/likers_fixtures.dart';

PostModel post({int likes = 123}) => PostModel.fromJson({
  'id': 10,
  'user_id': 2,
  'user': {'id': 2, 'name': 'Ahmed Adel'},
  'content': 'Bali was everything I needed.',
  'visibility': 'public',
  'likes_count': likes,
  'is_liked': true,
  'comments_count': 2,
  'is_saved': false,
});

void main() {
  late MemoryCommentsRepo comments;
  late PendingLikesRepo likeWrites;
  late LikesCubit likes;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('account-7');
    comments = MemoryCommentsRepo()
      ..items[1] = comment(1, content: 'Bali is really pure magic')
      ..items[2] = comment(2, parentId: 1, content: 'Agreed');
    likeWrites = PendingLikesRepo();
    likes = LikesCubit(repo: likeWrites);
  });
  tearDown(() async {
    await likes.close();
    await PreferencesManager().clear();
  });

  Future<void> show(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: BlocProvider.value(value: likes, child: screen),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('like count is singular only for exactly one', (tester) async {
    await show(tester, PostScreen(post: post(likes: 1), comments: comments));
    expect(find.text('1 Like'), findsOneWidget);
    expect(find.text('1 Likes'), findsNothing);
  });

  testWidgets('shows the post, inline comments and a pinned composer', (
    tester,
  ) async {
    await show(tester, PostScreen(post: post(), comments: comments));
    expect(find.text('Post'), findsOneWidget);
    expect(find.text('Ahmed Adel'), findsOneWidget);
    expect(find.text('Bali was everything I needed.'), findsOneWidget);
    expect(find.text('123 Likes'), findsOneWidget);
    expect(find.text('Comments'), findsOneWidget);
    expect(find.byType(CommentsThreadView), findsOneWidget);
    expect(find.text('Bali is really pure magic'), findsOneWidget);
    expect(find.text('View 1 reply'), findsOneWidget);
    expect(find.text('Add a comment'), findsOneWidget);
    // The composer is outside the scroll view, so it stays at the bottom.
    expect(
      find.ancestor(
        of: find.byType(TextField),
        matching: find.byType(CustomScrollView),
      ),
      findsNothing,
    );
  });

  testWidgets('like count opens "Liked by" and leaves the like alone', (
    tester,
  ) async {
    final likers = LikersRepo([
      [liker(8)],
    ]);
    await show(
      tester,
      PostScreen(post: post(), comments: comments, likers: likers),
    );
    await tester.tap(find.byKey(const ValueKey('post-likes-count')));
    await tester.pumpAndSettle();
    expect(find.byType(LikedBySheet), findsOneWidget);
    expect(find.text('User 8'), findsOneWidget);
    expect(likeWrites.writes, isEmpty);
  });

  testWidgets('heart toggles the like through the shared LikesCubit', (
    tester,
  ) async {
    await show(tester, PostScreen(post: post(), comments: comments));
    await tester.tap(find.byKey(const ValueKey('post-like')));
    await tester.pump();
    expect(likeWrites.writes.single.liked, isFalse);
    expect(find.text('122 Likes'), findsOneWidget);
  });

  testWidgets('a reply deep link opens its thread', (tester) async {
    await show(
      tester,
      PostScreen(
        post: post(),
        comments: comments,
        highlightCommentId: 2,
        highlightParentId: 1,
      ),
    );
    expect(find.byType(CommentsScreen), findsOneWidget);
    expect(find.text('Agreed'), findsOneWidget);
    // Let the highlight tint finish.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('⋮ sits in the app bar opposite back, not in the author row', (
    tester,
  ) async {
    await show(tester, PostScreen(post: post(), comments: comments));
    final more = find.byKey(const ValueKey('post-screen-more'));
    expect(more, findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppBar), matching: more),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(PostCard),
        matching: find.byType(MoreOptionsButton),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(PostCard),
        matching: find.byIcon(Icons.more_vert),
      ),
      findsNothing,
    );
    final back = find.byType(BackButtonWidget);
    final moreSize = tester.getSize(
      find.descendant(of: more, matching: find.byType(SizedBox)).first,
    );
    expect(moreSize, const Size(44, 44));
    expect(
      tester.getCenter(back).dy,
      moreOrLessEquals(tester.getCenter(more).dy),
    );
    expect(
      tester.getCenter(back).dx,
      moreOrLessEquals(390 - tester.getCenter(more).dx),
    );
  });

  testWidgets('app bar ⋮ opens the other-user post menu', (tester) async {
    final hidden = HiddenPostsCubit(repo: PostsRepo(), feeds: []);
    addTearDown(hidden.close);
    await show(
      tester,
      BlocProvider.value(
        value: hidden,
        child: PostScreen(post: post(), comments: comments),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('post-screen-more')));
    await tester.pumpAndSettle();
    expect(find.byType(PostOptionsSheet), findsOneWidget);
    expect(find.text('Not interested'), findsOneWidget);
    expect(find.text('Hide post'), findsOneWidget);
    expect(find.text('Report'), findsOneWidget);
    expect(find.text('Delete post'), findsNothing);
  });
}
