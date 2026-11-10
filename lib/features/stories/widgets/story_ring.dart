import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/stories/data/story_model.dart';

/// Paints over the avatar edge, so gaps show the actual photo beneath it.
/// The surrounding Home story cell retains its existing layout dimensions.
class StoryRing extends StatelessWidget {
  const StoryRing({
    super.key,
    required this.stories,
    required this.child,
    this.now,
  });
  final List<StorySummary> stories;
  final Widget child;
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
      foregroundPainter: StoryRingPainter(colors: colors),
      child: child,
    );
  }
}

class StoryRingPainter extends CustomPainter {
  StoryRingPainter({required List<Color> colors})
    : colors = List.unmodifiable(colors);

  final List<Color> colors;
  static const strokeWidth = 2.0;
  static const gapRadians = 3 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    if (colors.isEmpty || size.shortestSide <= strokeWidth) return;
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
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

  @override
  bool shouldRepaint(StoryRingPainter oldDelegate) =>
      !listEquals(colors, oldDelegate.colors);
}
