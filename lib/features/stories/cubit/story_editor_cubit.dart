import 'dart:ui';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/features/stories/data/story_audience.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';

class StoryEditorCubit extends Cubit<StoryEditorDraft> {
  StoryEditorCubit(super.initialState);
  int _nextId = 0;

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
    String newId;
    do {
      newId = 'story-text-${++_nextId}';
    } while (state.layers.any((layer) => layer.id == newId));
    emit(
      state.withLayers([
        ...state.layers,
        StoryTextLayer(id: newId, text: text),
      ]),
    );
  }

  /// Called only when a gesture finishes, never for pointer-move previews.
  void commitTransform(String id, Offset center, double scale) {
    if (isClosed ||
        !center.dx.isFinite ||
        !center.dy.isFinite ||
        !scale.isFinite ||
        scale <= 0) {
      return;
    }
    emit(
      state.withLayers([
        for (final layer in state.layers)
          if (layer is StoryTextLayer && layer.id == id)
            layer.copyWith(
              center: Offset(center.dx.clamp(0, 1), center.dy.clamp(0, 1)),
              scale: scale,
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
}
