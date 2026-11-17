import 'package:flutter/widgets.dart';
import 'package:travibe/core/widgets/upload_progress_ring.dart';
import 'package:travibe/core/widgets/travibe_toast.dart';
import 'package:travibe/features/stories/cubit/story_upload_cubit.dart';

/// The floating toast for a background Story upload, or null to clear it.
/// Mirrors posts: progress → green success, or red failure with Retry and X.
TravibeToastData? storyUploadToast(
  StoryUploadState state, {
  required VoidCallback onRetry,
  required VoidCallback onDiscard,
}) => switch (state) {
  StoryUploading(:final progress) => TravibeToastData.info(
    'Uploading your story',
    leading: UploadProgressRing(
      progress: progress,
      ringKey: const ValueKey('story-upload-progress'),
    ),
  ),
  StoryUploadFailed() => TravibeToastData.error(
    StoryUploadCubit.failureMessage,
    actionLabel: 'Retry',
    onAction: onRetry,
    onClose: onDiscard,
  ),
  StoryUploadDone() || StoryUploadIdle() => null,
};

const storyPublishedToast = TravibeToastData.success(
  'Story published successfully',
);
