import 'package:flutter/material.dart';

/// Full-screen viewer gesture: drag [child] down to dismiss it.
///
/// Releasing past [dismissDistance] or flinging down calls [onDismiss];
/// otherwise the content springs back. A second finger (pinch) cancels the
/// drag so zooming never closes the viewer. Turn [enabled] off while the
/// content is zoomed so panning wins the gesture.
class SwipeDownDismiss extends StatefulWidget {
  const SwipeDownDismiss({
    super.key,
    required this.child,
    required this.onDismiss,
    this.enabled = true,
    this.onDragChanged,
  });

  /// Drag distance (logical px) past which a release dismisses.
  static const dismissDistance = 120.0;
  static const _flingVelocity = 700.0;

  final Widget child;
  final VoidCallback onDismiss;
  final bool enabled;

  /// True when a dismiss drag starts, false when it settles back or ends.
  final ValueChanged<bool>? onDragChanged;

  @override
  State<SwipeDownDismiss> createState() => _SwipeDownDismissState();
}

class _SwipeDownDismissState extends State<SwipeDownDismiss>
    with SingleTickerProviderStateMixin {
  late final AnimationController _settle;
  final _pointers = <int>{};
  double _drag = 0;
  double _settleFrom = 0;
  bool _dragging = false;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _settle =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 180),
        )..addListener(
          () => setState(() => _drag = _settleFrom * (1 - _settle.value)),
        );
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _setDragging(bool value) {
    if (_dragging == value) return;
    _dragging = value;
    widget.onDragChanged?.call(value);
  }

  void _springBack() {
    _setDragging(false);
    if (_drag == 0) return;
    _settleFrom = _drag;
    _settle.forward(from: 0);
  }

  void _update(DragUpdateDetails details) {
    if (_dismissed) return;
    if (_pointers.length > 1) {
      if (_dragging) _springBack();
      return;
    }
    _settle.stop();
    _setDragging(true);
    setState(
      () => _drag = (_drag + details.delta.dy).clamp(0, double.infinity),
    );
  }

  void _end(DragEndDetails details) {
    if (_dismissed || !_dragging) return;
    final fling =
        (details.primaryVelocity ?? 0) > SwipeDownDismiss._flingVelocity;
    if (fling || _drag > SwipeDownDismiss.dismissDistance) {
      _dismissed = true;
      _setDragging(false);
      widget.onDismiss();
      return;
    }
    _springBack();
  }

  @override
  Widget build(BuildContext context) {
    final fade = (1 - _drag / 400).clamp(0.3, 1.0);
    return Listener(
      onPointerDown: (event) => _pointers.add(event.pointer),
      onPointerUp: (event) => _pointers.remove(event.pointer),
      onPointerCancel: (event) => _pointers.remove(event.pointer),
      child: GestureDetector(
        key: const ValueKey('swipe-down-dismiss'),
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: widget.enabled ? _update : null,
        onVerticalDragEnd: widget.enabled ? _end : null,
        onVerticalDragCancel: widget.enabled ? _springBack : null,
        child: Opacity(
          opacity: fade,
          child: Transform.translate(
            offset: Offset(0, _drag),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
