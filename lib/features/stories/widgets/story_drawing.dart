import 'package:flutter/material.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';

/// Paints normalized strokes onto any canvas size (editor preview and the
/// full-resolution flattened export use the same routine).
void paintStoryStrokes(
  Canvas canvas,
  Size size,
  Iterable<StoryStroke> strokes,
) {
  for (final stroke in strokes) {
    if (stroke.points.isEmpty) continue;
    final paint = Paint()
      ..color = Color(stroke.colorArgb)
      ..strokeWidth = stroke.width * size.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    Offset point(Offset p) => Offset(p.dx * size.width, p.dy * size.height);
    if (stroke.points.length == 1) {
      canvas.drawCircle(
        point(stroke.points.single),
        paint.strokeWidth / 2,
        paint..style = PaintingStyle.fill,
      );
      continue;
    }
    final path = Path()
      ..moveTo(point(stroke.points.first).dx, point(stroke.points.first).dy);
    for (final p in stroke.points.skip(1)) {
      final q = point(p);
      path.lineTo(q.dx, q.dy);
    }
    canvas.drawPath(path, paint);
  }
}

class StoryStrokesPainter extends CustomPainter {
  StoryStrokesPainter(this.strokes);
  final List<StoryStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) =>
      paintStoryStrokes(canvas, size, strokes);

  @override
  bool shouldRepaint(StoryStrokesPainter oldDelegate) =>
      !identical(oldDelegate.strokes, strokes);
}

/// Captures finger strokes over the canvas while drawing mode is active.
/// The in-progress stroke stays local; only a finished stroke is committed.
class StoryDrawingSurface extends StatefulWidget {
  const StoryDrawingSurface({
    super.key,
    required this.color,
    required this.width,
    required this.onStroke,
  });

  final Color color;

  /// Logical pixels at the current canvas width.
  final double width;
  final ValueChanged<StoryStroke> onStroke;

  @override
  State<StoryDrawingSurface> createState() => _StoryDrawingSurfaceState();
}

class _StoryDrawingSurfaceState extends State<StoryDrawingSurface> {
  List<Offset>? _points;
  Size _size = Size.zero;

  Offset _normalize(Offset local) => Offset(
    (local.dx / _size.width).clamp(0.0, 1.0),
    (local.dy / _size.height).clamp(0.0, 1.0),
  );

  StoryStroke? get _current => _points == null || _size.isEmpty
      ? null
      : StoryStroke(
          points: _points!,
          colorArgb: widget.color.toARGB32(),
          width: widget.width / _size.width,
        );

  void _end() {
    final stroke = _current;
    setState(() => _points = null);
    if (stroke != null) widget.onStroke(stroke);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _size = constraints.biggest;
      final current = _current;
      return GestureDetector(
        key: const ValueKey('story-drawing-surface'),
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) =>
            setState(() => _points = [_normalize(details.localPosition)]),
        onPanUpdate: (details) {
          if (_points == null) return;
          setState(
            () => _points = [..._points!, _normalize(details.localPosition)],
          );
        },
        onPanEnd: (_) => _end(),
        onPanCancel: () => setState(() => _points = null),
        child: CustomPaint(
          size: Size.infinite,
          painter: StoryStrokesPainter(current == null ? const [] : [current]),
        ),
      );
    },
  );
}
