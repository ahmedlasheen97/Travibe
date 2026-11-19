import 'dart:convert';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/home/data/home_account_repo.dart';

/// Last known Home account (name/avatar) for the signed-in session, so the
/// greeting shows offline and on cold start. Owned by the session token: a
/// different account never reads it, and logout's `clearSession` removes it.
class HomeAccountCache {
  HomeAccountCache({PreferencesManager? preferences})
    : _prefs = preferences ?? PreferencesManager();

  static const key = 'home_account_cache_v1';
  final PreferencesManager _prefs;
  int get sessionRevision => _prefs.sessionRevision;

  HomeAccount? read() {
    try {
      final owner = _prefs.sessionToken;
      if (owner == null || owner.isEmpty) return null;
      final raw = _prefs.getString(key);
      if (raw == null) return null;
      final data = jsonDecode(raw);
      if (data is! Map ||
          data['owner'] != owner ||
          data['id'] is! String ||
          data['name'] is! String) {
        return null;
      }
      return HomeAccount(
        id: data['id'] as String,
        name: data['name'] as String,
        avatarUrl: data['avatarUrl'] is String
            ? data['avatarUrl'] as String
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// Writes [account] for the current session unless [sessionRevision] is stale.
  Future<void> write(
    HomeAccount account, {
    required int sessionRevision,
  }) async {
    final owner = _prefs.sessionToken;
    if (owner == null ||
        owner.isEmpty ||
        sessionRevision != _prefs.sessionRevision) {
      return;
    }
    try {
      await _prefs.setString(
        key,
        jsonEncode({
          'owner': owner,
          'id': account.id,
          'name': account.name,
          'avatarUrl': account.avatarUrl,
        }),
      );
    } catch (_) {
      // Best effort: the cache only improves the offline greeting.
    }
  }
}
