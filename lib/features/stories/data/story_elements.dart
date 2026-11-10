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

  static List<Map<String, dynamic>> encode(List<StoryEditorLayer> layers) {
    if (layers.length > 50) {
      throw const FormatException('Maximum 50 text elements');
    }
    final ids = <String>{};
    return layers
        .map((layer) {
          if (layer is! StoryTextLayer ||
              layer.id.isEmpty ||
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
        })
        .toList(growable: false);
  }

  static List<StoryTextLayer> decode(dynamic json) {
    if (json is! List || json.length > 50) {
      throw const FormatException('Invalid Story elements');
    }
    final layers = <StoryTextLayer>[];
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
