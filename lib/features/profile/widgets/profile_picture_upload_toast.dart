import 'package:flutter/widgets.dart';
import 'package:travibe/core/widgets/travibe_toast.dart';

/// Sticky toasts stay until replaced, also on the SnackBar path outside Root.
const _sticky = Duration(days: 1);

/// The floating toast for a profile picture upload, or null to clear it.
/// Same as Stories: white progress ring → green success, or red failure
/// with Retry and X. [progress] is the leading ring; callers pass one that
/// rebuilds itself so progress ticks don't re-present a SnackBar.
TravibeToastData? profilePictureToast({
  required bool uploading,
  required bool failed,
  required Widget progress,
  required VoidCallback onRetry,
  required VoidCallback onDiscard,
}) {
  if (uploading) {
    return TravibeToastData(
      message: 'Uploading your picture',
      leading: progress,
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

const profileUpdatedToast = TravibeToastData.success('Profile updated');
