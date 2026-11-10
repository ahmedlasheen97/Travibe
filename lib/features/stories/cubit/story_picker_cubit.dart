import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';
import 'package:travibe/features/stories/data/story_photo_repo.dart';

part 'story_picker_state.dart';

class StoryPickerCubit extends Cubit<StoryPickerState> {
  StoryPickerCubit({StoryPhotoRepo? repo})
    : _repo = repo ?? StoryPhotoRepo(),
      super(const StoryPickerState());

  final StoryPhotoRepo _repo;

  Future<StoryEditorDraft?> pick() => _run(_repo.pick);
  Future<StoryEditorDraft?> capture() => _run(_repo.capture, camera: true);
  Future<StoryEditorDraft?> recover() => _run(_repo.recover);

  Future<StoryEditorDraft?> _run(
    Future<StoryEditorDraft?> Function() operation, {
    bool camera = false,
  }) async {
    if (isClosed || state.busy) return null;
    emit(StoryPickerState(busy: true, capturing: camera));
    try {
      final draft = await operation();
      if (isClosed) return null;
      emit(const StoryPickerState());
      return draft;
    } catch (error) {
      if (!isClosed) {
        emit(StoryPickerState(error: _message(error, camera: camera)));
      }
      return null;
    }
  }

  String _message(Object error, {required bool camera}) {
    if (error is InvalidStoryImage) {
      return 'This image could not be opened. Please choose another photo.';
    }
    if (error is MissingPluginException) {
      if (camera) return 'The camera is unavailable on this device.';
      return 'The photo picker is unavailable on this device.';
    }
    if (error is PlatformException) {
      if (error.code == 'camera_access_denied' ||
          error.code == 'camera_access_restricted') {
        return 'Camera access is restricted. Check your device settings.';
      }
      if (error.code == 'no_available_camera') {
        return 'The camera is unavailable on this device.';
      }
    }
    if (camera && (error is UnsupportedError || error is UnimplementedError)) {
      return 'The camera is unavailable on this device.';
    }
    if (error is PlatformException &&
        (error.code == 'photo_access_denied' ||
            error.code == 'photo_access_restricted')) {
      return 'Photo selection is restricted. Check your device settings.';
    }
    return camera
        ? 'Unable to take a photo. Please try again.'
        : 'Unable to open that photo. Please try again.';
  }
}
