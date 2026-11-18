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

  /// The element that carries hidden (@ tool) mentions.
  static const mentionsId = 'story-mentions';

  /// U+200B ZERO WIDTH SPACE, sent as the hidden element's `text`. The API
  /// trims strings (Laravel `TrimStrings` strips U+200B, then empty becomes
  /// null), so it is read back as `"text": null`. [decode] skips the element
  /// by its id either way; the mentions come from `content`.
  static const invisibleText = '\u200B';

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

  /// Text layers to draw. Never fails a Story because of one element: any
  /// element this build can't render is skipped (and logged in debug).
  ///
  /// The hidden mentions element is always skipped, however the server
  /// returns it. The API trims strings, so the [invisibleText] sent as its
  /// `text` comes back as `null`. Text that is empty or only whitespace or
  /// zero-width characters is skipped too. Stickers from earlier builds
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

  /// Whitespace and the zero-width/format characters the API trims (or that
  /// draw nothing): U+200B–U+200F, U+2060, U+FEFF.
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
