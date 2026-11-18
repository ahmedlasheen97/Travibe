import 'package:flutter/widgets.dart';
import 'package:travibe/core/widgets/upload_progress_ring.dart';
import 'package:travibe/core/widgets/travibe_toast.dart';
import 'package:travibe/features/stories/cubit/story_upload_cubit.dart';

/// The floating toast for a background Story upload, or null to clear it.
/// Mirrors posts: progress → green success, or red failure with Retry and X.
/// A mention 422 offers "Post anyway" (no hidden mentions) instead of Retry.
TravibeToastData? storyUploadToast(
  StoryUploadState state, {
  required VoidCallback onRetry,
  required VoidCallback onDiscard,
  VoidCallback? onPostWithoutMentions,
}) => switch (state) {
  StoryUploading(:final progress) => TravibeToastData.info(
    'Uploading your story',
    leading: UploadProgressRing(
      progress: progress,
      ringKey: const ValueKey('story-upload-progress'),
    ),
  ),
  StoryUploadFailed(mentionsRejected: true, :final message)
      when onPostWithoutMentions != null =>
    TravibeToastData.error(
      message,
      actionLabel: 'Post anyway',
      onAction: onPostWithoutMentions,
      onClose: onDiscard,
    ),
  StoryUploadFailed() => TravibeToastData.error(
    StoryUploadCubit.failureMessage,
    actionLabel: 'Retry',
    onAction: onRetry,
    onClose: onDiscard,
  ),
  StoryUploadDone() || StoryUploadIdle() => null,
};

/// The transient toast once a Story is posted.
TravibeToastData storyDoneToast(StoryUploadDone state) =>
    state.mentionsDropped ? storyMentionsDroppedToast : storyPublishedToast;

const storyPublishedToast = TravibeToastData.success(
  'Story published successfully',
);

/// Shown instead of [storyPublishedToast] when the server dropped some
/// hidden mentions (e.g. private accounts the author doesn't follow).
const storyMentionsDroppedToast = TravibeToastData.info(
  "Some people couldn't be mentioned",
);
