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

  void cycleMentionStyle(String id) {
    if (isClosed) return;
    emit(
      state.withLayers([
        for (final layer in state.layers)
          if (layer is StoryMentionLayer && layer.id == id)
            layer.copyWith(style: layer.style.next)
          else
            layer,
      ]),
    );
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
