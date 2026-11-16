import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/widgets/swipe_down_dismiss.dart';

void main() {
  late int dismissed;
  late List<bool> drags;

  Future<void> show(WidgetTester tester, {bool enabled = true}) async {
    dismissed = 0;
    drags = [];
    await tester.pumpWidget(
      MaterialApp(
        home: SwipeDownDismiss(
          enabled: enabled,
          onDismiss: () => dismissed++,
          onDragChanged: drags.add,
          child: const ColoredBox(
            key: ValueKey('content'),
            color: Colors.black,
            child: SizedBox.expand(),
          ),
        ),
      ),
    );
  }

  double offsetY(WidgetTester tester) => tester
      .widget<Transform>(
        find.ancestor(
          of: find.byKey(const ValueKey('content')),
          matching: find.byType(Transform),
        ),
      )
      .transform
      .getTranslation()
      .y;

  testWidgets('a drag past the threshold dismisses once', (tester) async {
    await show(tester);
    await tester.drag(
      find.byKey(const ValueKey('content')),
      const Offset(0, SwipeDownDismiss.dismissDistance + 60),
    );
    await tester.pumpAndSettle();
    expect(dismissed, 1);
    expect(drags, [true, false]);
  });

  testWidgets('a short drag springs back without dismissing', (tester) async {
    await show(tester);
    final gesture = await tester.startGesture(const Offset(200, 300));
    await gesture.moveBy(const Offset(0, 30));
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    expect(offsetY(tester), greaterThan(0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(dismissed, 0);
    expect(offsetY(tester), 0);
    expect(drags, [true, false]);
  });

  testWidgets('upward drags never move the content', (tester) async {
    await show(tester);
    await tester.drag(
      find.byKey(const ValueKey('content')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(dismissed, 0);
    expect(offsetY(tester), 0);
  });

  testWidgets('a second finger (pinch) cancels the dismiss drag', (
    tester,
  ) async {
    await show(tester);
    final first = await tester.startGesture(const Offset(200, 300));
    await first.moveBy(const Offset(0, 40));
    final second = await tester.startGesture(const Offset(220, 400));
    await first.moveBy(const Offset(0, 200));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(dismissed, 0);
    expect(offsetY(tester), 0);
  });

  testWidgets('disabled (e.g. zoomed) ignores the drag', (tester) async {
    await show(tester, enabled: false);
    await tester.drag(
      find.byKey(const ValueKey('content')),
      const Offset(0, 400),
    );
    await tester.pumpAndSettle();
    expect(dismissed, 0);
    expect(drags, isEmpty);
  });
}
