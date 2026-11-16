import 'package:flutter/material.dart';
import 'package:travibe/core/widgets/app_loaders.dart';
import 'package:travibe/core/widgets/travibe_toast.dart';

/// Sticky toasts stay until replaced, also on the SnackBar path outside Root.
const _sticky = Duration(days: 1);

/// The floating toast for a profile picture upload, or null to clear it.
/// Mirrors posts: spinner → green success, or red failure with Retry and X.
TravibeToastData? profilePictureToast({
  required bool uploading,
  required bool failed,
  required VoidCallback onRetry,
  required VoidCallback onDiscard,
}) {
  if (uploading) {
    return const TravibeToastData(
      message: 'Uploading your picture',
      leading: AppActivityIndicator(radius: 10),
      duration: _sticky,
    );
  }
  if (failed) {
    return TravibeToastData(
      message: 'Couldn’t upload your picture',
      variant: TravibeToastVariant.error,
      actionLabel: 'Retry',
      onAction: onRetry,
      onClose: onDiscard,
      duration: _sticky,
    );
  }
  return null;
}

const profilePictureUpdatedToast = TravibeToastData.success(
  'Picture updated successfully',
);
