part of 'story_picker_cubit.dart';

class StoryPickerState {
  const StoryPickerState({
    this.busy = false,
    this.capturing = false,
    this.error,
  });

  final bool busy;
  final bool capturing;
  final String? error;
}
