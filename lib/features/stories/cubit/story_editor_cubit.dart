import 'dart:ui';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/stories/data/story_audience.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';
import 'package:travibe/features/stories/data/story_elements.dart';

class StoryEditorCubit extends Cubit<StoryEditorDraft> {
  StoryEditorCubit(super.initialState);
  int _nextId = 0;

  /// Text layers (and the hidden mentions element) are API elements (max 50).
  static const maxElements = 50;
  static const maxEmojis = 30;

  /// Text layers, plus one element for hidden mentions when there are any.
  int get elementCount =>
      state.layers.whereType<StoryTextLayer>().length +
      (state.mentions.isEmpty ? 0 : 1);
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

  /// Mention sheet "Add": the people picked with the @ tool. Nothing is drawn
  /// on the story; they are sent as hidden mentions. Returns how many could
  /// not be kept (no id/username, or over [StoryElements.maxMentions]).
  int setMentions(List<PublicUserModel> users) {
    if (isClosed) return users.length;
    final mentions = <int, StoryMentionedUser>{};
    var rejected = 0;
    for (final user in users) {
      final id = int.tryParse(user.id);
      final username = user.username?.trim() ?? '';
      if (id == null || id <= 0 || username.isEmpty) {
        rejected++;
      } else if (!mentions.containsKey(id)) {
        if (mentions.length >= StoryElements.maxMentions) {
          rejected++;
        } else {
          mentions[id] = StoryMentionedUser(id: id, username: username);
        }
      }
    }
    // The hidden element counts towards the 50-element cap.
    if (mentions.isNotEmpty &&
        state.mentions.isEmpty &&
        elementCount >= maxElements) {
      return users.length;
    }
    emit(state.withMentions(mentions.values.toList()));
    return rejected;
  }

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
