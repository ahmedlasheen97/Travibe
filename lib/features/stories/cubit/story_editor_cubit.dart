import 'dart:ui';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/stories/data/story_audience.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';

class StoryEditorCubit extends Cubit<StoryEditorDraft> {
  StoryEditorCubit(super.initialState);
  int _nextId = 0;

  /// Text + mention layers are API elements (max 50).
  static const maxElements = 50;
  static const maxEmojis = 30;

  int get elementCount =>
      state.layers.where((layer) => layer is! StoryEmojiLayer).length;
  int get emojiCount => state.layers.whereType<StoryEmojiLayer>().length;

  String _newId(String prefix) {
    String id;
    do {
      id = 'story-$prefix-${++_nextId}';
    } while (state.layers.any((layer) => layer.id == id));
    return id;
  }

  void setAudience(StoryAudience audience) {
    if (isClosed || state.audience == audience) return;
    emit(state.withAudience(audience));
  }

  void saveText(String text, {String? id}) {
    if (isClosed || text.trim().isEmpty) return;
    if (id != null) {
      emit(
        state.withLayers([
          for (final layer in state.layers)
            if (layer is StoryTextLayer && layer.id == id)
              layer.copyWith(text: text)
            else
              layer,
        ]),
      );
      return;
    }
    emit(
      state.withLayers([
        ...state.layers,
        StoryTextLayer(id: _newId('text'), text: text),
      ]),
    );
  }

  /// Returns false when the user has no username/id or the cap is reached.
  bool addMention(PublicUserModel user) {
    final userId = int.tryParse(user.id);
    final username = user.username?.trim() ?? '';
    if (isClosed ||
        userId == null ||
        userId <= 0 ||
        username.isEmpty ||
        elementCount >= maxElements) {
      return false;
    }
    emit(
      state.withLayers([
        ...state.layers,
        StoryMentionLayer(
          id: _newId('mention'),
          userId: userId,
          username: username,
        ),
      ]),
    );
    return true;
  }

  /// Mention sheet "Add": keeps stickers for users still selected (with
  /// their position and style), removes unchecked ones and places new ones
  /// near the centre, stacked so they don't cover each other. Returns how
  /// many selected users could not be added (no id/username or the cap).
  int syncMentions(List<PublicUserModel> users) {
    if (isClosed) return users.length;
    final wanted = <int, String>{};
    var rejected = 0;
    for (final user in users) {
      final userId = int.tryParse(user.id);
      final username = user.username?.trim() ?? '';
      if (userId == null || userId <= 0 || username.isEmpty) {
        rejected++;
      } else {
        wanted.putIfAbsent(userId, () => username);
      }
    }
    final kept = <StoryEditorLayer>[];
    final present = <int>{};
    for (final layer in state.layers) {
      if (layer is StoryMentionLayer) {
        if (!wanted.containsKey(layer.userId) || !present.add(layer.userId)) {
          continue;
        }
      }
      kept.add(layer);
    }
    var elements = kept.where((layer) => layer is! StoryEmojiLayer).length;
    var placed = 0;
    for (final entry in wanted.entries) {
      if (present.contains(entry.key)) continue;
      if (elements >= maxElements) {
        rejected++;
        continue;
      }
      kept.add(
        StoryMentionLayer(
          id: _newId('mention'),
          userId: entry.key,
          username: entry.value,
          center: Offset(0.5, (0.5 + placed * 0.08).clamp(0.1, 0.9)),
        ),
      );
      elements++;
      placed++;
    }
    emit(state.withLayers(kept));
    return rejected;
  }

  /// Users with a sticker on the story, in sticker order.
  List<({int id, String username})> get mentionedUsers => [
    for (final layer in state.layers.whereType<StoryMentionLayer>())
      (id: layer.userId, username: layer.username),
  ];

  void setAllowReshare(bool allow) {
    if (isClosed || state.allowReshare == allow) return;
    emit(state.withAllowReshare(allow));
  }

  bool addEmoji(String emoji) {
    if (isClosed || emoji.trim().isEmpty || emojiCount >= maxEmojis) {
      return false;
    }
    emit(
      state.withLayers([
        ...state.layers,
        StoryEmojiLayer(id: _newId('emoji'), emoji: emoji),
      ]),
    );
    return true;
  }

  /// Called only when a gesture finishes, never for pointer-move previews.
  void commitTransform(
    String id,
    Offset center,
    double scale, {
    double rotation = 0,
  }) {
    if (isClosed ||
        !center.dx.isFinite ||
        !center.dy.isFinite ||
        !scale.isFinite ||
        scale <= 0 ||
        !rotation.isFinite) {
      return;
    }
    emit(
      state.withLayers([
        for (final layer in state.layers)
          if (layer.id == id)
            layer.transformed(
              center: Offset(center.dx.clamp(0, 1), center.dy.clamp(0, 1)),
              scale: scale,
              rotation: rotation,
            )
          else
            layer,
      ]),
    );
  }

  void removeLayer(String id) {
    if (!isClosed) {
      emit(
        state.withLayers(
          state.layers.where((layer) => layer.id != id).toList(),
        ),
      );
    }
  }

  void addStroke(StoryStroke stroke) {
    if (isClosed ||
        stroke.points.isEmpty ||
        !stroke.width.isFinite ||
        stroke.width <= 0 ||
        stroke.points.any((p) => !p.dx.isFinite || !p.dy.isFinite)) {
      return;
    }
    emit(state.withStrokes([...state.strokes, stroke]));
  }

  void undoStroke() {
    if (isClosed || state.strokes.isEmpty) return;
    emit(state.withStrokes(state.strokes.sublist(0, state.strokes.length - 1)));
  }
}
