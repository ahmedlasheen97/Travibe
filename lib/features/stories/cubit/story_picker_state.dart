part of 'story_picker_cubit.dart';

class StoryPickerState {
  const StoryPickerState({
    this.busy = false,
    this.capturing = false,
    this.error,
    this.permissionDenied,
  });

  final bool busy;
  final bool capturing;
  final String? error;

  /// A camera/photos denial; the sheet offers Settings instead of [error].
  final AppPermission? permissionDenied;
}
