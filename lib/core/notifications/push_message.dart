import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';

/// FCM transport envelope only. No Laravel recipient/deep-link schema is assumed.
class PushMessage {
  PushMessage({
    this.id,
    this.sentAt,
    this.title,
    this.body,
    Map<String, dynamic> data = const {},
  }) : data = Map.unmodifiable(data);

  factory PushMessage.fromRemote(RemoteMessage message) => PushMessage(
    id: message.messageId,
    sentAt: message.sentTime,
    title: message.notification?.title,
    body: message.notification?.body,
    data: message.data,
  );

  final String? id, title, body;
  final DateTime? sentAt;
  final Map<String, dynamic> data;

  String get key => id?.trim().isNotEmpty == true
      ? 'id:${id!.trim()}'
      : jsonEncode(
          _canonical({
            'time': sentAt?.toUtc().toIso8601String(),
            'title': title,
            'body': body,
            'data': data,
          }),
        );

  // JSON values supplied by the FCM SDK; map ordering must not defeat deduping.
  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.whereType<String>().toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    return null;
  }

  @override
  String toString() => 'PushMessage(redacted)';
}

enum PushActivityKind { foreground, opened, initial }

class PushActivity {
  const PushActivity(this.kind, this.sessionRevision);
  final PushActivityKind kind;
  final int sessionRevision;
}
