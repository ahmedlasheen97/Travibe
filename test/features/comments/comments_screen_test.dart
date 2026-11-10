import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/comments/widgets/comment_row.dart';
import 'package:travibe/features/comments/cubit/comments_cubit.dart';
import 'package:travibe/features/comments/screens/comments_screen.dart';
import 'fixtures.dart';

void main() {
  late MemoryCommentsRepo repo;
  late CommentsCubit cubit;
  setUp(() {
    repo = MemoryCommentsRepo();
    cubit = CommentsCubit(postId: 10, repo: repo);
  });
  tearDown(() => cubit.close());
  Future<void> show(WidgetTester tester, {bool disabled = false}) async {
    await cubit.load();
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          theme: darkTheme,
          home: BlocProvider.value(
            value: cubit,
            child: CommentsScreen(commentsDisabled: disabled),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'empty list can submit text and clears the composer only on success',
    (tester) async {
      await show(tester);
      expect(find.text('No comments yet'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'New comment');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      expect(find.text('Comments'), findsOneWidget);
      expect(find.text('1'), findsWidgets);
      expect(find.text('New comment'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    },
  );
  testWidgets(
    'inline replies share the Cubit and synchronize counts without navigation',
    (tester) async {
      repo.items[1] = comment(1);
      await show(tester);
      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
      expect(find.text('Replying to Sara'), findsOneWidget);
      expect(find.text('No replies yet'), findsOneWidget);
      expect(find.byType(CommentsScreen), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'A reply');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      expect(repo.items[100]!.parentId, 1);
      expect(find.text('A reply'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('comment-count'))).data,
        '2',
      );
      await tester.tap(find.text('Hide replies').first);
      await tester.pumpAndSettle();
      expect(find.text('A reply'), findsNothing);
      await tester.tap(find.text('View 1 replies'));
      await tester.pumpAndSettle();
      expect(find.text('A reply'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'backend failure retains the draft and shows the original message',
    (tester) async {
      await show(tester);
      repo.mutationError = ApiError(
        message: 'Comments disabled',
        statusCode: 422,
      );
      await tester.enterText(find.byType(TextField), 'Draft');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      expect(find.text('Comments disabled'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Draft',
      );
      expect(repo.items, isEmpty);
    },
  );
  testWidgets('disabled creation still permits an authorized text edit', (
    tester,
  ) async {
    repo.items[1] = comment(1);
    await show(tester, disabled: true);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Edited');
    await tester.pump();
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Edited'), findsOneWidget);
    expect(repo.writes, ['edit']);
    expect(find.byType(TextField), findsNothing);
  });
  testWidgets(
    'modal matches sheet geometry and keeps composer above keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => MaterialApp(
            theme: darkTheme,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => CommentsScreen.open(
                    context,
                    postId: 10,
                    repo: repo,
                    initialCount: 1200,
                  ),
                  child: const Text('Open comments'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open comments'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('1.2K'), findsOneWidget);
      final sheet = tester.getRect(find.byType(CommentsScreen));
      expect(sheet.top, 230);
      expect(sheet.height, 614);
      expect(tester.getTopLeft(find.text('Comments')).dx, 20);
      final input = tester.widget<TextField>(find.byType(TextField));
      expect(input.decoration!.filled, isFalse);
      expect(input.style!.color, Colors.white);
      expect(find.byTooltip('Send'), findsNothing);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(
        tester.getBottomLeft(find.byType(TextField)).dy,
        lessThanOrEqualTo(544),
      );
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 60));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    },
  );

  testWidgets('explicit row typography and avatar size ignore legacy theme', (
    tester,
  ) async {
    repo.items[1] = comment(1);
    await show(tester);
    final name = tester.widget<Text>(find.text('Sara'));
    expect(name.style!.fontSize, 14);
    expect(name.style!.fontWeight, FontWeight.w600);
    expect(name.style!.color, Colors.white);
    expect(name.style!.decoration, TextDecoration.none);
    final avatar = find.descendant(
      of: find.byType(CommentRow),
      matching: find.byType(ClipOval),
    );
    expect(tester.getSize(avatar), const Size(32, 32));
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading and failed reads recover through Retry', (tester) async {
    repo.holdReads = true;
    final pending = cubit.load();
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          home: BlocProvider.value(value: cubit, child: const CommentsScreen()),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repo.holdReads = false;
    repo.reads.single.result.completeError(
      ApiError(message: 'Connection failed'),
    );
    await pending;
    await tester.pumpAndSettle();
    expect(find.text('Connection failed'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No comments yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delete and restore remain available inside the sheet', (
    tester,
  ) async {
    repo.items[1] = comment(1);
    await show(tester);
    await tester.tap(find.byTooltip('Comment options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(repo.items, isEmpty);
    await tester.tap(find.text('Restore: Hello'));
    await tester.pumpAndSettle();
    expect(find.text('Hello'), findsOneWidget);
    expect(repo.writes, ['delete', 'restore']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reply pagination failure preserves replies and retries the next page',
    (tester) async {
      repo.items[1] = comment(1, content: 'Parent');
      for (var i = 2; i <= 4; i++) {
        repo.items[i] = comment(i, parentId: 1, content: 'Reply $i');
      }
      await show(tester);
      await tester.tap(find.text('View 3 replies'));
      await tester.pumpAndSettle();
      expect(find.text('Reply 4'), findsOneWidget);
      repo.readError = ApiError(message: 'Next page failed');
      await tester.ensureVisible(find.text('Load more replies'));
      await tester.tap(find.text('Load more replies'));
      await tester.pumpAndSettle();
      expect(find.text('Next page failed'), findsOneWidget);
      expect(find.text('Reply 4'), findsOneWidget);
      repo.readError = null;
      await tester.ensureVisible(find.text('Retry'));
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Reply 2'), findsOneWidget);
      expect(repo.reads.last.page, 2);
      expect(repo.reads.last.parentId, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
