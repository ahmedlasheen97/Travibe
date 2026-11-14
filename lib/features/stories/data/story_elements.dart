import 'dart:ui';

import 'package:travibe/features/stories/data/story_editor_draft.dart';

/// Client-owned v1 payload; the API stores elements verbatim. No API enums are
/// inferred from this schema. Unsupported versions/styles are rejected on read.
class StoryElements {
  static const style = <String, Object>{
    'font_family': 'Plus Jakarta Sans',
    'font_size': 24,
    'reference_width': 390,
    'font_weight': 600,
    'color_argb': 0xFFFFFFFF,
    'shadow_color_argb': 0xDD000000,
    'shadow_blur': 3,
    'padding': 8,
    'max_width_fraction': 0.8,
    'alignment': 'center',
    'direction': 'ltr',
  };

  /// Text and mention layers become elements. Emoji layers and strokes are
  /// flattened into the uploaded photo and are skipped here.
  ///
  /// A mention is a v1 text element whose text is `@username` (the API reads
  /// mentions from text elements) with the identical v1 `style`, plus optional
  /// `rotation` and `mention` keys. Older app builds ignore the extra keys and
  /// still render it as plain text instead of rejecting the Story.
  static List<Map<String, dynamic>> encode(List<StoryEditorLayer> layers) {
    final elements = layers.where((layer) => layer is! StoryEmojiLayer);
    if (elements.length > 50) {
      throw const FormatException('Maximum 50 text elements');
    }
    final ids = <String>{};
    return elements
        .map((layer) {
          final text = switch (layer) {
            StoryTextLayer(:final text) => text,
            StoryMentionLayer(:final text) => text,
            _ => '',
          };
          if (layer.id.isEmpty ||
              !ids.add(layer.id) ||
              text.trim().isEmpty ||
              !layer.center.dx.isFinite ||
              !layer.center.dy.isFinite ||
              layer.center.dx < 0 ||
              layer.center.dx > 1 ||
              layer.center.dy < 0 ||
              layer.center.dy > 1 ||
              !layer.scale.isFinite ||
              layer.scale <= 0 ||
              !layer.rotation.isFinite ||
              (layer is StoryMentionLayer &&
                  (layer.userId <= 0 || layer.username.isEmpty))) {
            throw const FormatException('Invalid Story text element');
          }
          return <String, dynamic>{
            'version': 1,
            'id': layer.id,
            'type': 'text',
            'text': text,
            'position': {'x': layer.center.dx, 'y': layer.center.dy},
            'scale': layer.scale,
            'style': Map<String, Object>.of(style),
            if (layer is StoryMentionLayer) ...{
              'rotation': layer.rotation,
              'mention': {
                'user_id': layer.userId,
                'username': layer.username,
                'style': layer.style.name,
              },
            },
          };
        })
        .toList(growable: false);
  }

  static List<StoryEditorLayer> decode(dynamic json) {
    if (json is! List || json.length > 50) {
      throw const FormatException('Invalid Story elements');
    }
    final layers = <StoryEditorLayer>[];
    for (final value in json) {
      if (value is! Map ||
          value['version'] is! int ||
          value['version'] != 1 ||
          value['type'] != 'text' ||
          value['id'] is! String ||
          value['text'] is! String ||
          value['position'] is! Map ||
          value['scale'] is! num ||
          value['style'] is! Map) {
        throw const FormatException('Unsupported Story element');
      }
      final appearance = value['style'] as Map;
      if (appearance.length != style.length ||
          !style.entries.every(
            (entry) => appearance[entry.key] == entry.value,
          )) {
        throw const FormatException('Unsupported Story text style');
      }
      final position = value['position'] as Map;
      if (position['x'] is! num || position['y'] is! num) {
        throw const FormatException('Invalid Story position');
      }
      final center = Offset(
        (position['x'] as num).toDouble(),
        (position['y'] as num).toDouble(),
      );
      final scale = (value['scale'] as num).toDouble();
      final mention = value['mention'];
      if (mention is Map &&
          mention['user_id'] is int &&
          mention['username'] is String &&
          value['text'] == '@${mention['username']}') {
        final rotation = value['rotation'];
        layers.add(
          StoryMentionLayer(
            id: value['id'],
            userId: mention['user_id'],
            username: mention['username'],
            style: StoryMentionStyle.parse(mention['style']),
            center: center,
            scale: scale,
            rotation: rotation is num ? rotation.toDouble() : 0,
          ),
        );
      } else {
        // Malformed mention metadata degrades to plain text, like old builds.
        layers.add(
          StoryTextLayer(
            id: value['id'],
            text: value['text'],
            center: center,
            scale: scale,
          ),
        );
      }
    }
    encode(layers); // Same bounds, uniqueness and finite-number validation.
    return List.unmodifiable(layers);
  }
}
