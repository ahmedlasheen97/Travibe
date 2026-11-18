import 'dart:ui' show ImageFilter;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';
import 'package:travibe/features/stories/widgets/story_mention_text.dart';

/// Shared layer geometry keeps editor hit testing, viewer rendering and the
/// flattened export aligned. Sizes are unscaled; [StoryEditorLayer.scale] and
/// rotation are applied around the layer center.
abstract class StoryLayerGeometry {
  StoryLayerGeometry();

  static StoryLayerGeometry of(
    StoryEditorLayer layer,
    Size canvas, {
    bool highlightMentions = true,
  }) => switch (layer) {
    StoryTextLayer() => StoryTextGeometry(
      layer,
      canvas,
      highlightMentions: highlightMentions,
    ),
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

/// Figma text bubble (`mention_view_profile.png`): white text in a dark
/// translucent rounded bubble (the story header pill's glass), with any
/// `@username` in orange. Editor and viewer share this.
class StoryTextGeometry extends StoryLayerGeometry {
  StoryTextGeometry(this.layer, Size canvas, {this.highlightMentions = true}) {
    final unit = canvas.width / 390;
    style = TextStyle(
      fontFamily: 'Plus Jakarta Sans',
      fontSize: 24 * unit,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    );
    padding = EdgeInsets.symmetric(horizontal: 16 * unit, vertical: 10 * unit);
    _maxTextWidth = math.max(1, canvas.width * 0.8 - padding.horizontal);
    final painter = _painter();
    lines = painter.computeLineMetrics().length;
    size = Size(
      painter.width + padding.horizontal,
      painter.height + padding.vertical,
    );
    painter.dispose();
    radius = math.min(size.height / 2, 24 * unit);
    maxScale = _maxScale(canvas, 4);
  }

  static final _blur = ImageFilter.blur(sigmaX: 10, sigmaY: 10);

  /// Spaces at the end of a line, which text layout would otherwise "hang"
  /// (they widen the bubble but aren't drawn where they are typed).
  static final _lineEndSpaces = RegExp(r' +(?=\n|$)');

  /// [StoryTextLayer.text] exactly as sent, with line-end spaces swapped for
  /// no-break spaces (same length, so text offsets still line up) so leading
  /// and trailing spaces both render where they are.
  late final String _displayText = layer.text.replaceAllMapped(
    _lineEndSpaces,
    (match) => '\u00A0' * match.group(0)!.length,
  );

  late final double _maxTextWidth;

  /// Same span, alignment and width as [content], so offsets line up.
  TextPainter _painter() => TextPainter(
    text: storyMentionTextSpan(_displayText, style),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout(maxWidth: _maxTextWidth);

  /// The `@handle` under [point] (unscaled, relative to this layer's
  /// top-left) and its rect in the same space, or null.
  (String, Rect)? mentionAt(Offset point) {
    final ranges = storyMentionRanges(layer.text);
    if (ranges.isEmpty) return null;
    final painter = _painter();
    try {
      final local = point - padding.topLeft;
      if (local.dx < 0 ||
          local.dy < 0 ||
          local.dx > painter.width ||
          local.dy > painter.height) {
        return null;
      }
      final offset = painter.getPositionForOffset(local).offset;
      for (final range in ranges) {
        if (offset < range.start || offset > range.end) continue;
        final boxes = painter.getBoxesForSelection(
          TextSelection(baseOffset: range.start, extentOffset: range.end),
        );
        if (boxes.isEmpty) continue;
        var rect = boxes.first.toRect();
        for (final box in boxes.skip(1)) {
          rect = rect.expandToInclude(box.toRect());
        }
        // A caret position at a word edge must still land inside the handle.
        if (!rect.inflate(2).contains(local)) continue;
        return (
          layer.text.substring(range.start + 1, range.end),
          rect.shift(padding.topLeft),
        );
      }
      return null;
    } finally {
      painter.dispose();
    }
  }

  final StoryTextLayer layer;

  /// Orange `@handle`s. Off for reshares, whose mentions aren't resolved.
  final bool highlightMentions;
  late final TextStyle style;
  late final EdgeInsets padding;
  late final double radius;

  /// Lines the text wraps onto.
  late final int lines;
  @override
  late final Size size;
  @override
  late final double maxScale;

  @override
  String get semanticLabel => 'Edit text: ${layer.text}';

  @override
  Widget content() {
    final shape = BorderRadius.circular(radius);
    return ClipRRect(
      key: const ValueKey('story-text-bubble'),
      borderRadius: shape,
      child: BackdropFilter(
        filter: _blur,
        child: DecoratedBox(
          // Same treatment as StoryGlass (the header pill).
          decoration: BoxDecoration(
            color: DarkColors.darkgreyColor.withValues(alpha: .6),
            borderRadius: shape,
            border: Border.all(color: Colors.white.withValues(alpha: .12)),
          ),
          child: Padding(
            padding: padding,
            child: RichText(
              textDirection: TextDirection.ltr,
              text: storyMentionTextSpan(
                _displayText,
                style,
                highlightMentions: highlightMentions,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
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
