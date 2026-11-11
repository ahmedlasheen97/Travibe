import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/theme/dark_theme.dart';
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

  Future<void> show(WidgetTester tester, int? highlight) async {
    await cubit.load();
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          theme: darkTheme,
          home: BlocProvider.value(
            value: cubit,
            child: CommentsScreen(highlightCommentId: highlight),
          ),
        ),
      ),
    );
  }

  BoxDecoration? tint(WidgetTester tester) {
    final container = find.ancestor(
      of: find.text('Target comment'),
      matching: find.byType(AnimatedContainer),
    );
    if (container.evaluate().isEmpty) return null;
    return tester.widget<AnimatedContainer>(container.first).decoration
        as BoxDecoration?;
  }

  testWidgets('notification comment is scrolled into view and tinted', (
    tester,
  ) async {
    repo.items[1] = comment(1, content: 'Other comment');
    repo.items[2] = comment(2, content: 'Target comment');
    await show(tester, 2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Target comment'), findsOneWidget);
    expect(tint(tester)!.color, isNot(Colors.transparent));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(tint(tester)!.color, Colors.transparent);
  });

  testWidgets('missing highlighted comment opens without error', (
    tester,
  ) async {
    repo.items[1] = comment(1, content: 'Other comment');
    await show(tester, 999);
    await tester.pumpAndSettle();
    expect(find.text('Other comment'), findsOneWidget);
    expect(tint(tester), isNull);
    expect(tester.takeException(), isNull);
  });
}
