import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/notifications/firebase_messaging_client.dart';
import 'package:travibe/core/notifications/push_notification_service.dart';
import 'package:travibe/core/notifications/push_notifications_host.dart';
import 'package:travibe/core/permissions/permission_sheet.dart';
import 'package:travibe/core/theme/dark_colors.dart';

/// Moments that may lead to the notifications soft ask.
enum NotificationPromptTrigger { afterSetup, firstChatMessage, firstFollow }

/// When the soft ask may appear: push is supported, the system has never
/// asked, the trigger hasn't produced a soft ask yet, and the last soft ask is
/// at least [cooldown] old. The device permission is device-wide, so these
/// values are kept on the device across logouts.
class NotificationPromptPolicy {
  NotificationPromptPolicy({
    PreferencesManager? preferences,
    DateTime Function()? clock,
    this.cooldown = const Duration(days: 3),
  }) : _preferences = preferences ?? PreferencesManager(),
       _clock = clock ?? DateTime.now;

  static const keyPrefix = PreferencesManager.notificationSoftAskPrefix;
  static const _lastShownKey = '${keyPrefix}last_shown';
  final PreferencesManager _preferences;
  final DateTime Function() _clock;
  final Duration cooldown;

  String _triggerKey(NotificationPromptTrigger trigger) =>
      '$keyPrefix${trigger.name}';

  bool shouldAsk(
    NotificationPromptTrigger trigger, {
    required bool supported,
    required PushPermission permission,
  }) {
    if (!supported || permission != PushPermission.notDetermined) return false;
    if (_preferences.getBool(_triggerKey(trigger)) == true) return false;
    final last = DateTime.tryParse(_preferences.getString(_lastShownKey) ?? '');
    return last == null || _clock().difference(last) >= cooldown;
  }

  Future<void> recordShown(NotificationPromptTrigger trigger) async {
    await Future.wait([
      _preferences.setBool(_triggerKey(trigger), true),
      _preferences.setString(_lastShownKey, _clock().toUtc().toIso8601String()),
    ]);
  }
}

/// "Turn on notifications" soft ask shown before the system prompt, so the
/// one-time system prompt only appears when the user has said yes.
abstract final class NotificationSoftAsk {
  /// Covers only the check-then-record window; once recorded, the policy's
  /// gap blocks duplicates, so a sheet torn down unanswered can't wedge this.
  static bool _deciding = false;

  /// Shows the soft ask for [trigger] when [NotificationPromptPolicy] allows
  /// it. "Turn On" opens the system prompt (Android 13+ POST_NOTIFICATIONS
  /// included). Returns true when the sheet was shown.
  static Future<bool> maybeShow(
    BuildContext context,
    NotificationPromptTrigger trigger, {
    PushNotificationService? push,
    NotificationPromptPolicy? policy,
  }) async {
    final service = push ?? PushNotificationsScope.maybeOf(context)?.service;
    if (service == null || _deciding) return false;
    _deciding = true;
    try {
      await service.start();
      if (!context.mounted) return false;
      final rules = policy ?? NotificationPromptPolicy();
      if (!rules.shouldAsk(
        trigger,
        supported: service.supported,
        permission: service.permission,
      )) {
        return false;
      }
      await rules.recordShown(trigger);
    } finally {
      _deciding = false;
    }
    if (!context.mounted) return false;
    final turnOn = await showPermissionSheet(
      context,
      sheetKey: const ValueKey('notification-soft-ask'),
      art: const _BellArt(),
      title: 'Turn on notifications',
      message:
          'Get notified when someone follows you, likes your posts or '
          'sends you a message',
      confirmLabel: 'Turn On',
    );
    if (turnOn) await service.requestPermission();
    return true;
  }
}

class _BellArt extends StatelessWidget {
  const _BellArt();

  @override
  Widget build(BuildContext context) {
    final size = AppSizes.adaptiveRadius(80);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: DarkColors.primaryColor.withValues(alpha: .16),
      ),
      child: SvgPicture.asset(
        'assets/images/icons/notification_bell.svg',
        width: size * .5,
        height: size * .5,
        colorFilter: const ColorFilter.mode(
          DarkColors.primaryColor,
          BlendMode.srcIn,
        ),
      ),
    );
  }
}
