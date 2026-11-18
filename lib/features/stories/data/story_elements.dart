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

  /// The element that carries hidden (@ tool) mentions.
  static const mentionsId = 'story-mentions';

  /// U+200B ZERO WIDTH SPACE: older builds draw nothing for it, and it is not
  /// whitespace to `String.trim`, so they still accept the element.
  static const invisibleText = '​';

  /// Most distinct mentions the API stores per story.
  static const maxMentions = 10;

  /// Text layers become v1 text elements. Emoji layers and strokes are
  /// flattened into the uploaded photo and are skipped here.
  ///
  /// [mentions] (picked with the @ tool, not drawn on the story) become one
  /// extra v1 text element: `text` is [invisibleText] and `content` is
  /// `"@a @b"`. The API reads mentions from both `text` and `content` of text
  /// elements, so these users are mentioned and notified, while older app
  /// builds render an invisible character instead of rejecting the Story.
  static List<Map<String, dynamic>> encode(
    List<StoryEditorLayer> layers, {
    List<StoryMentionedUser> mentions = const [],
  }) {
    final elements = layers.whereType<StoryTextLayer>().toList();
    if (elements.length + (mentions.isEmpty ? 0 : 1) > 50) {
      throw const FormatException('Maximum 50 text elements');
    }
    final ids = <String>{mentionsId};
    final encoded = elements.map((layer) {
      if (layer.id.isEmpty ||
          !ids.add(layer.id) ||
          layer.text.trim().isEmpty ||
          !layer.center.dx.isFinite ||
          !layer.center.dy.isFinite ||
          layer.center.dx < 0 ||
          layer.center.dx > 1 ||
          layer.center.dy < 0 ||
          layer.center.dy > 1 ||
          !layer.scale.isFinite ||
          layer.scale <= 0) {
        throw const FormatException('Invalid Story text element');
      }
      return <String, dynamic>{
        'version': 1,
        'id': layer.id,
        'type': 'text',
        'text': layer.text,
        'position': {'x': layer.center.dx, 'y': layer.center.dy},
        'scale': layer.scale,
        'style': Map<String, Object>.of(style),
      };
    }).toList();
    if (mentions.isNotEmpty) {
      if (mentions.length > maxMentions ||
          mentions.any((m) => m.id <= 0 || m.username.trim().isEmpty)) {
        throw const FormatException('Invalid Story mentions');
      }
      encoded.add({
        'version': 1,
        'id': mentionsId,
        'type': 'text',
        'text': invisibleText,
        'content': mentions.map((m) => '@${m.username}').join(' '),
        'position': {'x': 0.5, 'y': 0.5},
        'scale': 1,
        'style': Map<String, Object>.of(style),
        'mentions': [
          for (final m in mentions) {'user_id': m.id, 'username': m.username},
        ],
      });
    }
    return List.unmodifiable(encoded);
  }

  /// Text layers to draw. The hidden mentions element is skipped. Stickers
  /// from earlier builds (`mention` metadata) become ordinary text, so their
  /// `@username` shows highlighted in a text bubble.
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
      if (value['text'] == invisibleText) continue;
      final position = value['position'] as Map;
      if (position['x'] is! num || position['y'] is! num) {
        throw const FormatException('Invalid Story position');
      }
      layers.add(
        StoryTextLayer(
          id: value['id'],
          text: value['text'],
          center: Offset(
            (position['x'] as num).toDouble(),
            (position['y'] as num).toDouble(),
          ),
          scale: (value['scale'] as num).toDouble(),
        ),
      );
    }
    encode(layers); // Same bounds, uniqueness and finite-number validation.
    return List.unmodifiable(layers);
  }
}
