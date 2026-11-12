import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/navigation/bottom_nav_visibility.dart';

void main() {
  ScrollMetrics metrics(double pixels, {Axis axis = Axis.vertical}) =>
      FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 1000,
        pixels: pixels,
        viewportDimension: 500,
        axisDirection: axis == Axis.vertical
            ? AxisDirection.down
            : AxisDirection.right,
        devicePixelRatio: 1,
      );

  ScrollUpdateNotification update(
    double pixels,
    double delta, {
    bool drag = true,
    Axis axis = Axis.vertical,
  }) => ScrollUpdateNotification(
    metrics: metrics(pixels, axis: axis),
    context: _Context(),
    scrollDelta: delta,
    dragDetails: drag ? DragUpdateDetails(globalPosition: Offset.zero) : null,
  );

  late BottomNavVisibility nav;
  late int notifications;
  setUp(() {
    nav = BottomNavVisibility()..addListener(() => notifications++);
    notifications = 0;
  });
  tearDown(() => nav.dispose());

  test('user drag down hides; returns false so notifications bubble', () {
    expect(nav.handleScroll(update(120, 20)), isFalse);
    expect(nav.visible, isFalse);
  });

  test('a small upward movement shows again', () {
    nav.handleScroll(update(120, 20));
    nav.handleScroll(update(119, -1, drag: false));
    expect(nav.visible, isTrue);
  });

  test('forward user scroll direction shows', () {
    nav.hide();
    nav.handleScroll(
      UserScrollNotification(
        metrics: metrics(300),
        context: _Context(),
        direction: ScrollDirection.forward,
      ),
    );
    expect(nav.visible, isTrue);
  });

  test('reaching the top shows even without upward delta', () {
    nav.hide();
    nav.handleScroll(update(0, 0, drag: false));
    expect(nav.visible, isTrue);
  });

  test('momentum without a drag does not hide', () {
    nav.handleScroll(update(300, 30, drag: false));
    expect(nav.visible, isTrue);
  });

  test('horizontal scrolling is ignored', () {
    nav.handleScroll(update(200, 40, axis: Axis.horizontal));
    expect(nav.visible, isTrue);
    nav.hide();
    nav.handleScroll(update(0, -40, axis: Axis.horizontal));
    expect(nav.visible, isFalse);
  });

  test('bounce back past the end does not re-show', () {
    nav.hide();
    nav.handleScroll(update(1030, -10, drag: false));
    expect(nav.visible, isFalse);
  });

  test('listeners are notified only on change', () {
    nav.show();
    nav.hide();
    nav.hide();
    nav.handleScroll(update(300, 10));
    nav.show();
    expect(notifications, 2);
  });
}

class _Context extends Fake implements BuildContext {}
