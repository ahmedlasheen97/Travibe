import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/stories/data/story_model.dart';

/// Paints over the avatar edge, so gaps show the actual photo beneath it.
/// The surrounding Home story cell retains its existing layout dimensions.
/// Larger pictures (my Profile) pass a proportionally wider [strokeWidth] so
/// the ring reads the same as Home's.
class StoryRing extends StatelessWidget {
  const StoryRing({
    super.key,
    required this.stories,
    required this.child,
    this.strokeWidth = StoryRingPainter.strokeWidth,
    this.cornerRadius,
    this.now,
  });
  final List<StorySummary> stories;
  final Widget child;
  final double strokeWidth;

  /// Null paints a circle; otherwise a rounded rectangle along the child's
  /// edge with this outer corner radius (Home's rectangle story style).
  final double? cornerRadius;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final current = now?.call() ?? DateTime.now();
    final ids = <int>{};
    final colors = [
      for (final story in stories)
        if (story.expiresAt?.isAfter(current) == true && ids.add(story.id))
          story.hasSeen ? Colors.white24 : DarkColors.primaryColor,
    ];
    return CustomPaint(
      foregroundPainter: StoryRingPainter(
        colors: colors,
        width: strokeWidth,
        cornerRadius: cornerRadius,
      ),
      child: child,
    );
  }
}

class StoryRingPainter extends CustomPainter {
  StoryRingPainter({
    required List<Color> colors,
    this.width = strokeWidth,
    this.cornerRadius,
  }) : colors = List.unmodifiable(colors);

  final List<Color> colors;
  final double width;
  final double? cornerRadius;

  /// Home's ring width.
  static const strokeWidth = 2.0;
  static const gapRadians = 3 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    if (colors.isEmpty || size.shortestSide <= width) return;
    if (cornerRadius case final corner?) {
      _paintRoundedRect(canvas, size, corner);
      return;
    }
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - width) / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.butt
      ..isAntiAlias = true;
    if (colors.length == 1) {
      canvas.drawCircle(center, radius, paint..color = colors.single);
      return;
    }
    final step = 2 * math.pi / colors.length;
    // Defensive bound for unexpectedly dense data; never overlap/invert arcs.
    final gap = math.min(gapRadians, step / 3);
    final rect = Rect.fromCircle(center: center, radius: radius);
    for (var index = 0; index < colors.length; index++) {
      canvas.drawArc(
        rect,
        -math.pi / 2 + index * step + gap / 2,
        step - gap,
        false,
        paint..color = colors[index],
      );
    }
  }

  /// Same segment/gap rules as the circle, measured along the perimeter
  /// clockwise from top-center. A 3-degree gap is 3/360 of the perimeter.
  void _paintRoundedRect(Canvas canvas, Size size, double corner) {
    final rect = (Offset.zero & size).deflate(width / 2);
    final r = math.max(
      0.0,
      math.min(corner - width / 2, rect.shortestSide / 2),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.butt
      ..isAntiAlias = true;
    if (colors.length == 1) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(r)),
        paint..color = colors.single,
      );
      return;
    }
    final path = roundedRectPath(rect, r);
    final metric = path.computeMetrics().first;
    final total = metric.length;
    final step = total / colors.length;
    final gap = math.min(total * gapRadians / (2 * math.pi), step / 3);
    for (var index = 0; index < colors.length; index++) {
      final start = index * step + gap / 2;
      canvas.drawPath(
        metric.extractPath(start, start + step - gap),
        paint..color = colors[index],
      );
    }
  }

  /// Closed clockwise rounded-rect path starting at the top edge's center.
  @visibleForTesting
  static Path roundedRectPath(Rect rect, double r) {
    final arc = Radius.circular(r);
    return Path()
      ..moveTo(rect.center.dx, rect.top)
      ..lineTo(rect.right - r, rect.top)
      ..arcToPoint(Offset(rect.right, rect.top + r), radius: arc)
      ..lineTo(rect.right, rect.bottom - r)
      ..arcToPoint(Offset(rect.right - r, rect.bottom), radius: arc)
      ..lineTo(rect.left + r, rect.bottom)
      ..arcToPoint(Offset(rect.left, rect.bottom - r), radius: arc)
      ..lineTo(rect.left, rect.top + r)
      ..arcToPoint(Offset(rect.left + r, rect.top), radius: arc)
      ..close();
  }

  @override
  bool shouldRepaint(StoryRingPainter oldDelegate) =>
      width != oldDelegate.width ||
      cornerRadius != oldDelegate.cornerRadius ||
      !listEquals(colors, oldDelegate.colors);
}
