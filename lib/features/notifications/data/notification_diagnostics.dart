import 'package:flutter/foundation.dart';
import 'notification_model.dart';
import 'notification_presentation.dart';

/// No payload values, actor/target IDs, message text, URLs or credentials.
class NotificationDiagnostics {
  NotificationDiagnostics({
    void Function(String)? log,
    this.enabled = kDebugMode,
  }) : _log = log ?? debugPrint;
  final bool enabled;
  final void Function(String) _log;
  final Set<String> _reported = {};
  void inspect(InboxNotification item) {
    if (!enabled ||
        NotificationPresentationResolver.laravelTypes.containsKey(item.type) ||
        !_reported.add(item.type)) {
      return;
    }
    if (_reported.length > 64) _reported.remove(_reported.first);
    _log(
      '[Notifications] unsupported type fingerprint=${item.type.hashCode.toUnsigned(32).toRadixString(16)} '
      'targetPresent=${item.targetType != null && item.targetId != null} payloadKeyCount=${item.data.length}',
    );
  }
}
