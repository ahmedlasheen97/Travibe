import 'package:flutter/cupertino.dart' hide RefreshCallback;
import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';

/// Every loading indicator in the app is white. Circular and linear
/// indicators get it from `darkTheme.progressIndicatorTheme`; Cupertino
/// spinners and pull-to-refresh have no theme hook, so use these widgets.
const Color appLoaderColor = DarkColors.whiteColor;

/// [CupertinoActivityIndicator] that defaults to [appLoaderColor].
class AppActivityIndicator extends StatelessWidget {
  const AppActivityIndicator({
    super.key,
    this.radius = 10,
    this.animating = true,
    this.color,
  }) : progress = null;

  /// Pull-to-refresh drag state (`CupertinoActivityIndicator.partiallyRevealed`).
  const AppActivityIndicator.partiallyRevealed({
    super.key,
    this.radius = 10,
    double this.progress = 1,
    this.color,
  }) : animating = false;

  final double radius;
  final bool animating;

  /// Non-null for [AppActivityIndicator.partiallyRevealed].
  final double? progress;
  final Color? color;

  @override
  Widget build(BuildContext context) => switch (progress) {
    final progress? => CupertinoActivityIndicator.partiallyRevealed(
      radius: radius,
      progress: progress,
      color: color ?? appLoaderColor,
    ),
    null => CupertinoActivityIndicator(
      radius: radius,
      animating: animating,
      color: color ?? appLoaderColor,
    ),
  };
}

/// [RefreshIndicator] with a white spinner.
class AppRefreshIndicator extends StatelessWidget {
  const AppRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
    this.displacement = 40,
    this.edgeOffset = 0,
    this.notificationPredicate = defaultScrollNotificationPredicate,
  });

  final RefreshCallback onRefresh;
  final Widget child;
  final double displacement, edgeOffset;
  final ScrollNotificationPredicate notificationPredicate;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRefresh,
    displacement: displacement,
    edgeOffset: edgeOffset,
    notificationPredicate: notificationPredicate,
    color: appLoaderColor,
    child: child,
  );
}
