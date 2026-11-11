import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:travibe/core/theme/dark_colors.dart';

const double _radius = 12;

Widget _indicator(BuildContext context, {double? progress}) => Semantics(
  label: 'Refreshing',
  liveRegion: progress == null,
  excludeSemantics: true,
  child: progress == null
      ? CupertinoActivityIndicator(
          color: DarkColors.primaryColor,
          radius: _radius,
          animating: !MediaQuery.disableAnimationsOf(context),
        )
      : CupertinoActivityIndicator.partiallyRevealed(
          color: DarkColors.primaryColor,
          radius: _radius,
          progress: progress,
        ),
);

/// iOS-style indicator for [CupertinoSliverRefreshControl] (leading-edge lists).
Widget chatRefreshIndicatorBuilder(
  BuildContext context,
  RefreshIndicatorMode mode,
  double pulledExtent,
  double triggerDistance,
  double indicatorExtent,
) {
  final progress = (pulledExtent / triggerDistance).clamp(0.0, 1.0);
  return Center(
    child: switch (mode) {
      RefreshIndicatorMode.inactive => const SizedBox.shrink(),
      RefreshIndicatorMode.drag => _indicator(context, progress: progress),
      RefreshIndicatorMode.done => Opacity(
        opacity: progress,
        child: _indicator(context),
      ),
      _ => _indicator(context),
    },
  );
}

/// Pull-down refresh for a reversed (bottom-anchored) chat history, whose
/// visual top is the trailing edge that [CupertinoSliverRefreshControl] cannot
/// observe. The child scrollable must use bouncing physics so it overscrolls.
class ChatPullToRefresh extends StatefulWidget {
  const ChatPullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.triggerDistance = 80,
  });
  final Future<void> Function() onRefresh;
  final Widget child;
  final double triggerDistance;
  @override
  State<ChatPullToRefresh> createState() => _ChatPullToRefreshState();
}

class _ChatPullToRefreshState extends State<ChatPullToRefresh> {
  double _pulled = 0;
  bool _armed = false, _refreshing = false;

  bool _onScroll(ScrollNotification event) {
    final metrics = event.metrics;
    if (event.depth != 0 || metrics.axis != Axis.vertical) return false;
    final over = math.max(
      0.0,
      metrics.axisDirection == AxisDirection.up
          ? metrics.pixels - metrics.maxScrollExtent
          : metrics.minScrollExtent - metrics.pixels,
    );
    final dragging = switch (event) {
      ScrollUpdateNotification(:final dragDetails) => dragDetails != null,
      OverscrollNotification(:final dragDetails) => dragDetails != null,
      _ => false,
    };
    if (!_refreshing) {
      if (dragging) {
        _armed = over >= widget.triggerDistance;
      } else if (_armed &&
          (event is ScrollUpdateNotification ||
              event is ScrollEndNotification)) {
        _armed = false;
        _start();
      }
    }
    if (over != _pulled) setState(() => _pulled = over);
    return false;
  }

  Future<void> _start() async {
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh();
    } catch (_) {
      /* The refresh owner reports its own errors. */
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_pulled / widget.triggerDistance).clamp(0.0, 1.0);
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Stack(
        children: [
          widget.child,
          if (_refreshing || progress > 0)
            Positioned(
              key: const ValueKey('chat-pull-refresh-indicator'),
              top: 12,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: _indicator(
                    context,
                    progress: _refreshing ? null : progress,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
