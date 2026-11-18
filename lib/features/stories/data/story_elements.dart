import 'dart:ui';

import 'package:flutter/foundation.dart';

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

  /// The legacy element that carried hidden (@ tool) mentions before
  /// `mention_user_ids`. No longer sent; [decode] still skips it on old
  /// stories (whose `text` now comes back as `"\u200B"`).
  static const mentionsId = 'story-mentions';

  /// Most distinct `mention_user_ids` the API accepts per story.
  static const maxMentions = 10;

  /// Text layers become v1 text elements. Emoji layers and strokes are
  /// flattened into the uploaded photo and are skipped here. Hidden (@ tool)
  /// mentions are sent as `mention_user_ids`, not as an element.
  static List<Map<String, dynamic>> encode(List<StoryEditorLayer> layers) {
    final elements = layers.whereType<StoryTextLayer>().toList();
    if (elements.length > 50) {
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
    return List.unmodifiable(encoded);
  }

  /// Text layers to draw. Never fails a Story because of one element: any
  /// element this build can't render is skipped (and logged in debug).
  ///
  /// The legacy hidden mentions element is always skipped, whatever its
  /// `text` (`"\u200B"` now, `null` on stories saved while the API trimmed
  /// strings). Text comes back exactly as sent; text that is empty or only
  /// whitespace or zero-width characters is skipped (no empty bubble). Stickers from earlier builds
  /// (`mention` metadata) become ordinary text, so their `@username` shows
  /// highlighted in a text bubble. Throws only when [json] isn't a list.
  static List<StoryEditorLayer> decode(dynamic json) {
    if (json is! List) throw const FormatException('Invalid Story elements');
    final layers = <StoryEditorLayer>[];
    final ids = <String>{};
    for (final (index, value) in json.indexed) {
      if (value is Map && value['id'] == mentionsId) continue;
      final reason = _unsupported(value);
      if (reason != null) {
        if (reason.isNotEmpty) _skip(index, reason);
        continue;
      }
      final element = value as Map;
      if (layers.length >= 50) {
        _skip(index, 'more than 50 text elements');
        continue;
      }
      if (!ids.add(element['id'] as String)) {
        _skip(index, 'duplicate id');
        continue;
      }
      final position = element['position'] as Map;
      layers.add(
        StoryTextLayer(
          id: element['id'],
          text: element['text'],
          center: Offset(
            (position['x'] as num).toDouble(),
            (position['y'] as num).toDouble(),
          ),
          scale: (element['scale'] as num).toDouble(),
        ),
      );
    }
    return List.unmodifiable(layers);
  }

  /// Whitespace and the zero-width/format characters that draw nothing: U+200B–U+200F, U+2060, U+FEFF.
  static final _blank = RegExp(r'^[\s​-‏⁠﻿]*$');

  /// Why [value] can't be drawn, `''` to skip it silently (nothing to draw),
  /// or null when it is a renderable v1 text element.
  static String? _unsupported(dynamic value) {
    if (value is! Map) return 'not an object';
    if (value['version'] != 1) return 'unsupported version ${value['version']}';
    if (value['type'] != 'text') return 'unsupported type ${value['type']}';
    final text = value['text'];
    if (text == null || (text is String && _blank.hasMatch(text))) return '';
    if (text is! String) return 'text is not a string';
    final id = value['id'];
    if (id is! String || id.isEmpty) return 'missing id';
    final appearance = value['style'];
    if (appearance is! Map ||
        appearance.length != style.length ||
        !style.entries.every((entry) => appearance[entry.key] == entry.value)) {
      return 'unsupported text style';
    }
    final position = value['position'];
    if (position is! Map) return 'missing position';
    final x = position['x'], y = position['y'], scale = value['scale'];
    if (x is! num || y is! num || !_unit(x) || !_unit(y)) {
      return 'invalid position';
    }
    if (scale is! num || !scale.isFinite || scale <= 0) return 'invalid scale';
    return null;
  }

  static bool _unit(num value) => value.isFinite && value >= 0 && value <= 1;

  static void _skip(int index, String reason) {
    if (kDebugMode) {
      debugPrint('StoryElements: skipped element $index: $reason');
    }
  }
}
