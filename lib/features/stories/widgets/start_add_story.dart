import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/features/stories/cubit/story_picker_cubit.dart';
import 'package:travibe/features/stories/cubit/story_upload_cubit.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';
import 'package:travibe/features/stories/data/story_photo_repo.dart';
import 'package:travibe/features/stories/screens/story_editor_screen.dart';
import 'package:travibe/features/stories/widgets/post_story_sheet.dart';

/// Navigators with a picker sheet or editor opened by [startAddStory] still
/// up, so a second tap (from Home or Profile) never stacks another flow.
/// Keyed by navigator: if one is torn down mid-flow (e.g. a session change),
/// its replacement starts unblocked.
final _busyNavigators = Expando<bool>('startAddStory');

/// The one "add story" flow (picker sheet → editor → upload) shared by Home's
/// "You" bubble and the Profile picture's "+". It opens over the current
/// screen and never changes tabs.
///
/// When the app's [StoryUploadCubit] is in scope the editor hands the story to
/// it (Root shows the upload toast and announces the publication); otherwise
/// the editor publishes itself and calls [onPublished].
///
/// Pass [picker] to reuse a caller-owned picker (Home keeps one for Android
/// activity recovery); otherwise a temporary one is created and closed.
Future<void> startAddStory(
  BuildContext context, {
  StoryPickerCubit? picker,
  StoryPhotoRepo? photoRepo,
  String? avatarUrl,
  StoriesRepo? storiesRepo,
  Future<void> Function()? onPublished,
  ValueChanged<StoryUploadJob>? onSubmit,
}) async {
  final navigator = Navigator.of(context);
  if (_busyNavigators[navigator] == true) return;
  _busyNavigators[navigator] = true;
  final owned = picker == null ? StoryPickerCubit(repo: photoRepo) : null;
  try {
    final draft = await PostStorySheet.show(context, picker ?? owned!);
    if (!context.mounted || draft == null) return;
    await openStoryEditor(
      context,
      draft,
      avatarUrl: avatarUrl,
      storiesRepo: storiesRepo,
      onPublished: onPublished,
      onSubmit: onSubmit,
    );
  } finally {
    _busyNavigators[navigator] = null;
    if (owned != null) unawaited(owned.close());
  }
}

/// Pushes the Story editor for [draft] (also used for Android recovery).
Future<void> openStoryEditor(
  BuildContext context,
  StoryEditorDraft draft, {
  String? avatarUrl,
  StoriesRepo? storiesRepo,
  Future<void> Function()? onPublished,
  ValueChanged<StoryUploadJob>? onSubmit,
}) {
  final submit = onSubmit ?? context.read<StoryUploadCubit?>()?.enqueue;
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => StoryEditorScreen(
        draft: draft,
        avatarUrl: avatarUrl,
        storiesRepo: storiesRepo,
        onPublished: onPublished,
        onSubmit: submit,
      ),
    ),
  );
}
