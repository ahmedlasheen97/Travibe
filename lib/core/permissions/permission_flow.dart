import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:travibe/core/permissions/app_permission.dart';
import 'package:travibe/core/permissions/device_settings.dart';
import 'package:travibe/core/permissions/permission_sheet.dart';

/// The one place features go when a device permission blocks them.
///
/// The first request is always the system prompt, made when the feature is
/// tapped (image_picker for camera/photos, the native bridge for microphone,
/// Firebase for notifications). Once the system can no longer ask, this shows
/// the shared sheet with "Open Settings" / "Not Now".
abstract final class PermissionFlow {
  /// The permission behind a picker or native-bridge [error], if any.
  static AppPermission? fromError(Object error) => switch (error) {
    PlatformException(
      code: 'camera_access_denied' || 'camera_access_restricted',
    ) =>
      AppPermission.camera,
    PlatformException(
      code: 'photo_access_denied' || 'photo_access_restricted',
    ) =>
      AppPermission.photos,
    // Only the add-only gallery save of the native bridge uses this code.
    PlatformException(code: 'permission_denied') => AppPermission.photosAdd,
    _ => null,
  };

  /// Shows the settings sheet when [error] is a permission denial. Returns
  /// false for other errors so the caller keeps its own message.
  static Future<bool> handleError(BuildContext context, Object error) async {
    final permission = fromError(error);
    if (permission == null) return false;
    await showSettings(context, permission);
    return true;
  }

  /// Explains why [permission] is needed; "Open Settings" opens the app page
  /// in system Settings. If Settings can't be opened, says where to go.
  static Future<void> showSettings(
    BuildContext context,
    AppPermission permission, {
    DeviceSettings settings = const DeviceSettings(),
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!await showPermissionSettingsSheet(context, permission)) return;
    if (!await settings.open()) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Open Settings › Travibe to change this permission.'),
        ),
      );
    }
  }
}
