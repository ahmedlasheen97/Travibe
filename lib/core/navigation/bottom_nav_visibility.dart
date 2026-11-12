import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Shared show/hide state for Root's bottom navigation bar. One instance is
/// owned by Root and exposed to the tabs through [BottomNavScope].
class BottomNavVisibility extends ChangeNotifier {
  static const duration = Duration(milliseconds: 200);
  static const curve = Curves.easeOutCubic;

  bool _visible = true;
  bool get visible => _visible;

  void show() => _set(true);
  void hide() => _set(false);

  void _set(bool value) {
    if (_visible == value) return;
    _visible = value;
    notifyListeners();
  }

  /// Hides on a user drag towards later content, shows on any upward
  /// movement or when the list is back at its top. Never consumes [n].
  bool handleScroll(ScrollNotification n) {
    final metrics = n.metrics;
    if (metrics.axis != Axis.vertical) return false;
    if (metrics.pixels <= metrics.minScrollExtent) {
      show();
      return false;
    }
    if (n is UserScrollNotification) {
      if (n.direction == ScrollDirection.forward) show();
      return false;
    }
    // Ignore the bounce past the end so it does not re-show the bar.
    if (n is! ScrollUpdateNotification || metrics.outOfRange) return false;
    final delta = n.scrollDelta ?? 0;
    if (delta > 0 && n.dragDetails != null) {
      hide();
    } else if (delta < 0) {
      show();
    }
    return false;
  }
}

class BottomNavScope extends InheritedNotifier<BottomNavVisibility> {
  const BottomNavScope({
    super.key,
    required BottomNavVisibility visibility,
    required this.barHeight,
    required super.child,
  }) : super(notifier: visibility);

  /// Full bar height incl. the system inset, measured by Root outside the
  /// Scaffold (whose body strips the bottom view padding).
  final double barHeight;

  @override
  bool updateShouldNotify(BottomNavScope oldWidget) =>
      barHeight != oldWidget.barHeight || super.updateShouldNotify(oldWidget);

  static BottomNavVisibility? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BottomNavScope>()?.notifier;

  /// Bottom clearance a scrollable inside Root needs so its last item can
  /// scroll above the bar. Zero outside Root (e.g. pushed screens).
  static double bottomInsetOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<BottomNavScope>()?.barHeight ?? 0;
}

/// Slides [child] down out of view by shrinking its layout height, so the
/// Scaffold's floating SnackBars follow the bar.
class HideableBottomBar extends StatelessWidget {
  const HideableBottomBar({
    super.key,
    required this.visibility,
    required this.child,
  });
  final BottomNavVisibility visibility;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: visibility,
    builder: (context, child) {
      final visible = visibility.visible;
      return TweenAnimationBuilder<double>(
        tween: Tween(end: visible ? 1 : 0),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : BottomNavVisibility.duration,
        curve: BottomNavVisibility.curve,
        child: child,
        builder: (context, t, child) => IgnorePointer(
          ignoring: !visible,
          child: ExcludeSemantics(
            excluding: !visible,
            child: ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: t,
                child: child,
              ),
            ),
          ),
        ),
      );
    },
    child: child,
  );
}
