import 'package:flutter/foundation.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';

/// Private, memory-only route snapshots. Never shared across session revisions.
class ChatHistoryCache {
  ChatHistoryCache({PreferencesManager? preferences})
    : _preferences = preferences ?? PreferencesManager() {
    _session = _preferences.sessionRevision;
    _preferences.addListener(_checkSession);
  }
  static final instance = ChatHistoryCache();
  final PreferencesManager _preferences;
  late int _session;
  final _values = <Object, Object>{};
  final _bounded = <String, Map<Object, Object>>{};
  void _checkSession() {
    if (_session != _preferences.sessionRevision || !_preferences.hasSession) {
      _values.clear();
      _bounded.clear();
      _session = _preferences.sessionRevision;
    }
  }

  T? read<T>(Object key, {String? group}) {
    _checkSession();
    if (group == null) return _values[key] as T?;
    final bucket = _bounded[group];
    final value = bucket?.remove(key);
    if (value != null) bucket![key] = value;
    return value as T?;
  }

  void write(
    Object key,
    Object value,
    int session, {
    String? group,
    int maxEntries = 8,
  }) {
    _checkSession();
    if (!_preferences.hasSession || session != _session) return;
    if (group == null) {
      _values[key] = value;
      return;
    }
    assert(maxEntries > 0);
    final bucket = _bounded.putIfAbsent(group, () => <Object, Object>{});
    bucket.remove(key);
    bucket[key] = value;
    while (bucket.length > maxEntries) {
      bucket.remove(bucket.keys.first);
    }
  }

  void dispose() {
    _preferences.removeListener(_checkSession);
    _values.clear();
    _bounded.clear();
  }
}

/// Temporary opt-in diagnostics. Fixed labels/counts only; no content or URLs.
void chatLoadDiagnostic(String stage, {int? count}) {
  if (kDebugMode && const bool.fromEnvironment('CHAT_LOADING_DIAGNOSTICS')) {
    debugPrint('Chat lifecycle: $stage count=${count ?? 0}');
  }
}
