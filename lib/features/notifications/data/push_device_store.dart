import 'dart:convert';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';

/// Only user IDs and backend record IDs, never FCM or authorization tokens.
/// Entries survive logout so only the same confirmed user can retry cleanup.
class PushDeviceStore {
  PushDeviceStore({PreferencesManager? preferences})
    : _preferences = preferences ?? PreferencesManager();
  final PreferencesManager _preferences;
  Future<void> _tail = Future.value();

  Map<String, List<String>> _read() {
    try {
      final value = jsonDecode(
        _preferences.getString(PreferencesManager.pushDeviceRecordsKey) ?? '{}',
      );
      if (value is! Map) return {};
      return {
        for (final entry in value.entries)
          if (entry.key is String && entry.value is List)
            entry.key as String: (entry.value as List)
                .whereType<String>()
                .where((id) => RegExp(r'^[1-9][0-9]*$').hasMatch(id))
                .toSet()
                .toList(),
      };
    } catch (_) {
      return {};
    }
  }

  List<String> ids(String userId) => List.unmodifiable(_read()[userId] ?? []);
  Future<void> remember(String userId, String id) => _change(userId, id, true);
  Future<void> forget(String userId, String id) => _change(userId, id, false);
  Future<void> _change(String userId, String id, bool add) {
    final job = _tail.then((_) async {
      final records = _read();
      final ids = records[userId] ?? <String>[];
      ids.remove(id);
      if (add) ids.add(id);
      if (ids.isEmpty) {
        records.remove(userId);
      } else {
        records[userId] = ids;
      }
      if (!await _preferences.setString(
        PreferencesManager.pushDeviceRecordsKey,
        jsonEncode(records),
      )) {
        throw StateError('Unable to save device registration metadata.');
      }
    });
    _tail = job.then<void>((_) {}, onError: (Object _) {});
    return job;
  }
}
