import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';

/// Shared layer geometry keeps editor hit testing, viewer rendering and the
/// flattened export aligned. Sizes are unscaled; [StoryEditorLayer.scale] and
/// rotation are applied around the layer center.
abstract class StoryLayerGeometry {
  StoryLayerGeometry();

  static StoryLayerGeometry of(StoryEditorLayer layer, Size canvas) =>
      switch (layer) {
        StoryTextLayer() => StoryTextGeometry(layer, canvas),
        StoryMentionLayer() => StoryMentionGeometry(layer, canvas),
        StoryEmojiLayer() => StoryEmojiGeometry(layer, canvas),
        _ => throw ArgumentError.value(layer, 'layer', 'Unknown Story layer'),
      };

  Size get size;
  double get maxScale;

  /// The layer's rendered content at scale 1.
  Widget content();
  String get semanticLabel;

  double fitScale(double scale) =>
      scale.clamp(math.min(0.5, maxScale), maxScale);

  Offset bound(Offset center, double scale, Size canvas) {
    final halfWidth = math.min(0.5, size.width * scale / canvas.width / 2);
    final halfHeight = math.min(0.5, size.height * scale / canvas.height / 2);
    return Offset(
      center.dx.clamp(halfWidth, 1 - halfWidth),
      center.dy.clamp(halfHeight, 1 - halfHeight),
    );
  }

  double _maxScale(Size canvas, double cap) => math.min(
    cap,
    math.min(canvas.width / size.width, canvas.height / size.height),
  );

  /// Hit rectangle (ignoring rotation) for a layer drawn at [scale]/[center].
  Rect rect(Offset center, double scale, Size canvas) => Rect.fromCenter(
    center: Offset(center.dx * canvas.width, center.dy * canvas.height),
    width: size.width * scale,
    height: size.height * scale,
  );
}

class StoryTextGeometry extends StoryLayerGeometry {
  StoryTextGeometry(this.layer, Size canvas) {
    style = TextStyle(
      fontFamily: 'Plus Jakarta Sans',
      fontSize: 24 * canvas.width / 390,
      fontWeight: FontWeight.w600,
      color: Colors.white,
      shadows: const [Shadow(color: Colors.black87, blurRadius: 3)],
    );
    final painter = TextPainter(
      text: TextSpan(text: layer.text, style: style),
      textDirection: TextDirection.ltr,
    );
    painter.layout(maxWidth: math.max(1, canvas.width * 0.8 - 16));
    size = painter.size + const Offset(16, 16);
    painter.dispose();
    maxScale = _maxScale(canvas, 4);
  }
  final StoryTextLayer layer;
  late final TextStyle style;
  @override
  late final Size size;
  @override
  late final double maxScale;

  @override
  String get semanticLabel => 'Edit text: ${layer.text}';

  @override
  Widget content() => Padding(
    padding: const EdgeInsets.all(8),
    child: RichText(
      textDirection: TextDirection.ltr,
      text: TextSpan(text: layer.text, style: style),
      textAlign: TextAlign.center,
    ),
  );
}

class StoryMentionGeometry extends StoryLayerGeometry {
  StoryMentionGeometry(this.layer, Size canvas) {
    final unit = canvas.width / 390;
    final (background, foreground) = colors(layer.style);
    this.background = background;
    style = TextStyle(
      fontFamily: 'Plus Jakarta Sans',
      fontSize: 20 * unit,
      fontWeight: FontWeight.w700,
      color: foreground,
      shadows: layer.style == StoryMentionStyle.plain
          ? const [Shadow(color: Colors.black87, blurRadius: 3)]
          : null,
    );
    padding = EdgeInsets.symmetric(horizontal: 12 * unit, vertical: 6 * unit);
    radius = 8 * unit;
    final painter = TextPainter(
      text: TextSpan(text: layer.text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    );
    painter.layout(maxWidth: math.max(1, canvas.width * 0.8));
    size = Size(
      painter.width + padding.horizontal,
      painter.height + padding.vertical,
    );
    painter.dispose();
    maxScale = _maxScale(canvas, 4);
  }

  static (Color?, Color) colors(StoryMentionStyle style) => switch (style) {
    StoryMentionStyle.light => (Colors.white, Colors.black),
    StoryMentionStyle.dark => (const Color(0xCC000000), Colors.white),
    StoryMentionStyle.brand => (DarkColors.primaryColor, Colors.white),
    StoryMentionStyle.plain => (null, Colors.white),
  };

  final StoryMentionLayer layer;
  late final TextStyle style;
  late final Color? background;
  late final EdgeInsets padding;
  late final double radius;
  @override
  late final Size size;
  @override
  late final double maxScale;

  @override
  String get semanticLabel => 'Mention ${layer.text}';

  @override
  Widget content() => DecoratedBox(
    key: ValueKey('story-mention-${layer.style.name}'),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(radius),
    ),
    child: Padding(
      padding: padding,
      child: Text(
        layer.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textDirection: TextDirection.ltr,
        style: style,
      ),
    ),
  );
}

class StoryEmojiGeometry extends StoryLayerGeometry {
  StoryEmojiGeometry(this.layer, Size canvas) {
    final unit = canvas.width / 390;
    style = TextStyle(fontSize: 64 * unit, height: 1.15);
    padding = 4 * unit;
    final painter = textPainter(layer.emoji, style);
    size = Size(painter.width + padding * 2, painter.height + padding * 2);
    painter.dispose();
    maxScale = _maxScale(canvas, 5);
  }

  /// Also used by the flattener so the baked emoji matches the preview.
  static TextPainter textPainter(String emoji, TextStyle style) => TextPainter(
    text: TextSpan(text: emoji, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();

  final StoryEmojiLayer layer;
  late final TextStyle style;
  late final double padding;
  @override
  late final Size size;
  @override
  late final double maxScale;

  @override
  String get semanticLabel => 'Emoji ${layer.emoji}';

  @override
  Widget content() => Padding(
    padding: EdgeInsets.all(padding),
    child: Text(
      layer.emoji,
      maxLines: 1,
      textDirection: TextDirection.ltr,
      style: style,
    ),
  );
}
