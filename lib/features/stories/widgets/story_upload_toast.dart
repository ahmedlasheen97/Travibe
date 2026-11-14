import 'package:flutter/material.dart';
import 'package:travibe/core/widgets/app_loaders.dart';
import 'package:travibe/core/widgets/travibe_toast.dart';
import 'package:travibe/features/stories/cubit/story_upload_cubit.dart';

/// White determinate ring for the "Uploading your story" toast.
class StoryUploadProgressRing extends StatelessWidget {
  const StoryUploadProgressRing({super.key, required this.progress});

  /// 0..1; 0 shows an indeterminate spinner while the photo is prepared.
  final double progress;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Upload ${(progress * 100).round()}%',
    child: progress <= 0
        ? const AppActivityIndicator(radius: 10)
        : CircularProgressIndicator(
            key: const ValueKey('story-upload-progress'),
            value: progress.clamp(0.0, 1.0),
            strokeWidth: 2.5,
            color: appLoaderColor,
            backgroundColor: Colors.white24,
          ),
  );
}

/// The floating toast for a background Story upload, or null to clear it.
/// Mirrors posts: progress → green success, or red failure with Retry and X.
TravibeToastData? storyUploadToast(
  StoryUploadState state, {
  required VoidCallback onRetry,
  required VoidCallback onDiscard,
}) => switch (state) {
  StoryUploading(:final progress) => TravibeToastData.info(
    'Uploading your story',
    leading: StoryUploadProgressRing(progress: progress),
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
