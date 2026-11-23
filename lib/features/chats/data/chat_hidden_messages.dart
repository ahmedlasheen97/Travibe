import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';

/// "Delete for me": message IDs hidden on this device, per account.
///
/// The API has no delete-for-me endpoint yet (see docs/BACKEND_REQUESTS.md),
/// so hidden messages are filtered out client-side. Only IDs are stored,
/// never message content.
class ChatHiddenMessages extends ChangeNotifier {
  ChatHiddenMessages({PreferencesManager? preferences})
    : _preferences = preferences ?? PreferencesManager();

  static final instance = ChatHiddenMessages();

  /// Oldest IDs are dropped past this many per account.
  static const maxIds = 2000;

  final PreferencesManager _preferences;
  final _cache = <String, Set<String>>{};

  String _key(String userId) =>
      '${PreferencesManager.chatHiddenMessagesPrefix}$userId';

  /// Hidden IDs for [userId]; empty without an account.
  Set<String> ids(String? userId) {
    if (userId == null || userId.isEmpty) return const {};
    return _cache.putIfAbsent(userId, () {
      final raw = _preferences.getString(_key(userId));
      if (raw == null) return <String>{};
      try {
        final decoded = jsonDecode(raw);
        return decoded is List
            ? {
                for (final id in decoded)
                  if (id is String) id,
              }
            : <String>{};
      } on FormatException {
        return <String>{};
      }
    });
  }

  Future<void> hide(String? userId, String messageId) async {
    if (userId == null || userId.isEmpty || messageId.isEmpty) return;
    final current = ids(userId);
    if (current.contains(messageId)) return;
    final next = {...current, messageId};
    final kept = next.length > maxIds
        ? next.skip(next.length - maxIds).toSet()
        : next;
    _cache[userId] = kept;
    notifyListeners();
    await _preferences.setString(_key(userId), jsonEncode(kept.toList()));
  }
}
