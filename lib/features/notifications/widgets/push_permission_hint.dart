import 'dart:async';
import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/notifications/firebase_messaging_client.dart';
import 'package:travibe/core/notifications/push_notification_service.dart';
import 'package:travibe/core/theme/dark_colors.dart';

/// Subtle device-permission line under Settings → Push Notifications.
/// Shows nothing while the device can receive pushes (or push is
/// unsupported here); the account toggle is a separate, server-side setting.
class PushPermissionHint extends StatelessWidget {
  const PushPermissionHint({super.key, required this.push});
  final PushNotificationService push;

  static bool _undecided(PushPermission p) =>
      p == PushPermission.notDetermined || p == PushPermission.unknown;

  String? _message() {
    if (!push.supported) return null;
    return switch (push.permission) {
      PushPermission.notDetermined =>
        'Notifications aren’t allowed on this device yet.',
      PushPermission.denied =>
        'Notifications are blocked on this device. Allow them in device '
            'Settings, then check again.',
      PushPermission.unknown => null,
      PushPermission.authorized || PushPermission.provisional =>
        push.tokenStatus == PushTokenStatus.waitingForApns
            ? 'Waiting for Apple notification registration.'
            : push.error,
    };
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: push,
    builder: (context, _) {
      final message = _message();
      if (message == null) return const SizedBox.shrink();
      final enable = _undecided(push.permission);
      final style = TextStyle(fontSize: AppSizes.sp12);
      return Padding(
        key: const ValueKey('push-permission-hint'),
        padding: EdgeInsets.only(top: AppSizes.h4),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSizes.w4,
          children: [
            Text(message, style: style.copyWith(color: Colors.white54)),
            TextButton(
              key: const ValueKey('push-permission-action'),
              onPressed: push.requestingPermission
                  ? null
                  : () => unawaited(
                      enable ? push.requestPermission() : push.retry(),
                    ),
              style: TextButton.styleFrom(
                foregroundColor: DarkColors.primaryColor,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: style.copyWith(fontWeight: FontWeight.w600),
              ),
              child: Text(
                push.requestingPermission
                    ? 'Checking…'
                    : enable
                    ? 'Enable'
                    : 'Check',
              ),
            ),
          ],
        ),
      );
    },
  );
}
