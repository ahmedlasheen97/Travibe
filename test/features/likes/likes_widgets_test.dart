import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/post_card.dart';
import 'package:travibe/features/comments/cubit/comments_cubit.dart';
import 'package:travibe/features/comments/screens/comments_screen.dart';
import 'package:travibe/features/likes/cubit/likes_cubit.dart';
import 'package:travibe/features/likes/data/like_model.dart';
import '../comments/fixtures.dart' as comments;
import 'fixtures.dart';

void main() {
  late PendingLikesRepo repo;
  late LikesCubit likes;
  setUp(() {
    repo = PendingLikesRepo();
    likes = LikesCubit(repo: repo);
  });
  tearDown(() => likes.close());

  Future<void> show(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  SvgPicture heart(WidgetTester tester, Finder button) =>
      tester.widget<SvgPicture>(
        find.descendant(of: button, matching: find.byType(SvgPicture)),
      );

  void expectHeart(SvgPicture image, bool liked) {
    expect(image.colorFilter, isNull);
    expect(
      (image.bytesLoader as SvgAssetLoader).assetName,
      liked
          ? 'assets/images/interactions/heart.svg'
          : 'assets/images/interactions/heart2.svg',
    );
  }

  testWidgets(
    'post heart changes immediately, disables pending taps and rolls back failure',
    (tester) async {
      const target = LikeTarget.post(10);
      const initial = LikeValue(isLiked: false, count: 4);
      await show(
        tester,
        BlocBuilder<LikesCubit, LikesState>(
          bloc: likes,
          builder: (context, state) {
            final value = state.values[target] ?? initial;
            return PostCard(
              name: 'Sara',
              avatar: null,
              time: 'Now',
              text: 'Post',
              likes: '${value.count}',
              comments: '0',
              isLiked: value.isLiked,
              isLikePending: value.pending,
              onLikeTap: () async {
                final error = await likes.toggle(target, initial: initial);
                if (error != null && context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(error.message)));
                }
              },
            );
          },
        ),
      );
      final button = find.byKey(const ValueKey('post-like'));
      expectHeart(heart(tester, button), false);
      expect(heart(tester, button).width, 18);
      await tester.tap(button);
      await tester.pump();
      expectHeart(heart(tester, button), true);
      expect(find.text('5'), findsOneWidget);
      await tester.tap(button);
      expect(repo.writes, hasLength(1));
      repo.writes.single.result.complete(
        const LikeValue(isLiked: true, count: 9),
      );
      await tester.pumpAndSettle();
      expect(find.text('9'), findsOneWidget);
      await tester.tap(button);
      await tester.pump();
      expectHeart(heart(tester, button), false);
      expect(find.text('8'), findsOneWidget);
      repo.writes.last.result.completeError(
        ApiError(message: 'Network unavailable'),
      );
      await tester.pumpAndSettle();
      expectHeart(heart(tester, button), true);
      expect(find.text('9'), findsOneWidget);
      expect(find.text('Network unavailable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'comment and inline reply use the same SVG behavior and preserve composer',
    (tester) async {
      final source = comments.MemoryCommentsRepo()
        ..items[1] = comments.comment(1, replies: 1)
        ..items[2] = comments.comment(2, parentId: 1, content: 'Reply text');
      final cubit = CommentsCubit(postId: 10, repo: source, likes: likes);
      addTearDown(cubit.close);
      await cubit.load();
      await show(
        tester,
        BlocProvider.value(value: cubit, child: const CommentsScreen()),
      );
      await tester.enterText(find.byType(TextField), 'Draft stays');
      final button = find.byKey(const ValueKey('comment-like-1'));
      expectHeart(heart(tester, button), false);
      expect(heart(tester, button).width, 20);
      await tester.tap(button);
      await tester.pump();
      expectHeart(heart(tester, button), true);
      await tester.tap(button);
      expect(repo.writes, hasLength(1));
      repo.writes.single.result.complete(
        const LikeValue(isLiked: true, count: 1),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('View 1 reply'));
      await tester.pumpAndSettle();
      final reply = find.byKey(const ValueKey('comment-like-2'));
      await tester.ensureVisible(reply);
      expectHeart(heart(tester, reply), false);
      await tester.tap(reply);
      await tester.pump();
      expectHeart(heart(tester, reply), true);
      expect(repo.writes.last.target, const LikeTarget.comment(10, 2));
      repo.writes.last.result.completeError(
        ApiError(message: 'Comment unavailable', statusCode: 404),
      );
      await tester.pumpAndSettle();
      expectHeart(heart(tester, reply), false);
      expect(find.text('Comment unavailable'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Draft stays',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reopened bottom sheet reads shared liked state', (tester) async {
    final source = comments.MemoryCommentsRepo()
      ..items[1] = comments.comment(1);
    await show(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => CommentsScreen.open(
            context,
            postId: 10,
            repo: source,
            likes: likes,
          ),
          child: const Text('Open comments'),
        ),
      ),
    );
    await tester.tap(find.text('Open comments'));
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('comment-like-1'));
    await tester.tap(button);
    await tester.pump();
    Navigator.of(tester.element(find.byType(CommentsScreen))).pop();
    await tester.pumpAndSettle();
    // Reopen before confirmation: the pending shared state survives disposal.
    await tester.tap(find.text('Open comments'));
    await tester.pumpAndSettle();
    expectHeart(heart(tester, button), true);
    repo.writes.single.result.complete(
      const LikeValue(isLiked: true, count: 1),
    );
    await tester.pumpAndSettle();
    expectHeart(heart(tester, button), true);
    expect(tester.takeException(), isNull);
  });
}
