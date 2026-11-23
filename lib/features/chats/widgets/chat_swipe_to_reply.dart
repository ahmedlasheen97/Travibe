import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Swipe a message toward the reading direction (right in LTR, left in RTL)
/// to reply. A reply arrow follows the drag; past [threshold] a haptic fires
/// and releasing calls [onReply].
///
/// Drags the other way, or mostly vertical ones, are rejected early so list
/// scrolling and nested horizontal scrollables keep their gestures.
class ChatSwipeToReply extends StatefulWidget {
  const ChatSwipeToReply({
    super.key,
    required this.child,
    required this.onReply,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback onReply;
  final bool enabled;

  /// Drag distance that arms the reply.
  static const threshold = 56.0;

  /// Furthest the bubble moves.
  static const maxOffset = 72.0;

  @override
  State<ChatSwipeToReply> createState() => _ChatSwipeToReplyState();
}

class _ChatSwipeToReplyState extends State<ChatSwipeToReply>
    with SingleTickerProviderStateMixin {
  late final AnimationController _settle;
  double _drag = 0, _settleFrom = 0;
  bool _armed = false;

  bool get _rtl => Directionality.of(context) == TextDirection.rtl;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addListener(_settling);
  }

  /// Shown offset: follows the finger, then resists up to [maxOffset].
  double get _offset {
    const t = ChatSwipeToReply.threshold;
    final eased = _drag <= t ? _drag : t + (_drag - t) * .35;
    return math.min(eased, ChatSwipeToReply.maxOffset);
  }

  void _settling() {
    setState(
      () => _drag = _settleFrom * (1 - Curves.easeOut.transform(_settle.value)),
    );
  }

  void _start(DragStartDetails _) {
    _settle.stop();
    _armed = false;
  }

  void _update(DragUpdateDetails details) {
    final forward = _rtl ? -details.delta.dx : details.delta.dx;
    setState(() => _drag = math.max(0, _drag + forward));
    final armed = _drag >= ChatSwipeToReply.threshold;
    if (armed && !_armed) HapticFeedback.lightImpact();
    _armed = armed;
  }

  void _end([DragEndDetails? _]) {
    if (_armed && widget.enabled) widget.onReply();
    _armed = false;
    _settleFrom = _drag;
    if (_drag == 0) return;
    _settle.forward(from: 0);
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offset = _offset;
    final progress = (offset / ChatSwipeToReply.threshold).clamp(0.0, 1.0);
    // Same tree when disabled so bubble state (players, images) survives.
    return RawGestureDetector(
      gestures: {
        if (widget.enabled)
          _ForwardDragRecognizer:
              GestureRecognizerFactoryWithHandlers<_ForwardDragRecognizer>(
                () => _ForwardDragRecognizer(debugOwner: this),
                (recognizer) => recognizer
                  ..rtl = (() => _rtl)
                  ..onStart = _start
                  ..onUpdate = _update
                  ..onEnd = _end
                  ..onCancel = _end,
              ),
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Center(
                child: Opacity(
                  opacity: progress,
                  child: Transform.scale(
                    scale: .6 + .4 * progress,
                    child: Container(
                      key: const ValueKey('chat-swipe-reply-arrow'),
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: Colors.white12,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.reply,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(_rtl ? -offset : offset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// Horizontal drag that bows out unless the finger heads toward the reading
/// direction and mostly sideways.
class _ForwardDragRecognizer extends HorizontalDragGestureRecognizer {
  _ForwardDragRecognizer({super.debugOwner});

  bool Function() rtl = () => false;
  final _starts = <int, Offset>{};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _starts[event.pointer] = event.position;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    final start = _starts[event.pointer];
    if (start != null && event is PointerMoveEvent) {
      final delta = event.position - start;
      if (delta.distance > kTouchSlop / 2) {
        _starts.remove(event.pointer);
        final forward = rtl() ? -delta.dx : delta.dx;
        if (forward <= 0 || delta.dy.abs() > forward) {
          resolvePointer(event.pointer, GestureDisposition.rejected);
          return;
        }
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _starts.remove(event.pointer);
    }
    super.handleEvent(event);
  }

  @override
  void rejectGesture(int pointer) {
    _starts.remove(pointer);
    super.rejectGesture(pointer);
  }
}
