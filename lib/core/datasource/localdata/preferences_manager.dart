import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/constants/app_languages.dart';
import 'package:travibe/features/stories/data/story_style.dart';

class PreferencesManager extends ChangeNotifier {
  static final PreferencesManager _instance = PreferencesManager._internal();
  factory PreferencesManager() {
    return _instance;
  }
  PreferencesManager._internal();

  late SharedPreferences _preferences;
  String? _sessionToken;
  int _sessionRevision = 0;
  int get sessionRevision => _sessionRevision;
  bool get hasSession => _sessionToken?.isNotEmpty == true;

  /// Current token; identifies the account owning per-session caches.
  String? get sessionToken => _sessionToken;
  final ValueNotifier<String> language = ValueNotifier('en');
  final ValueNotifier<String?> currency = ValueNotifier(null);

  /// Debug-only Home stories shape experiment; release builds stay circle.
  final ValueNotifier<StoryStyle> storyStyle = ValueNotifier(StoryStyle.circle);

  void _setSession(String? token) {
    if (_sessionToken == token) return;
    _sessionToken = token;
    currency.value = null;
    _sessionRevision++;
    notifyListeners();
  }

  final String _token = '_token';
  final String _languageKey = 'selected_language';
  final String _currencyKey = 'selected_currency';
  static const onboardingCompletedKey = 'onboarding_completed';
  static const pushDeviceRecordsKey = 'push_device_records_v1';
  static const notificationSoftAskPrefix = 'notification_soft_ask_';

  /// Device-wide debug preference; kept across logout.
  static const storyStyleKey = 'debug_story_style';

  /// Per-account "Delete for me" message IDs (`ChatHiddenMessages`); kept on
  /// logout so they stay hidden when the same account signs back in.
  static const chatHiddenMessagesPrefix = 'chat_hidden_messages_';

  bool get onboardingCompleted =>
      _preferences.getBool(onboardingCompletedKey) ?? false;

  Future<void> completeOnboarding() async {
    if (!await _preferences.setBool(onboardingCompletedKey, true)) {
      throw StateError('Unable to save onboarding completion.');
    }
  }

  Future<void> init() async {
    _preferences = await SharedPreferences.getInstance();
    _setSession(_preferences.getString(_token));
    // A saved language the app can't run in (Arabic during the MVP) is English.
    language.value = effectiveAppLanguage(_preferences.getString(_languageKey));
    currency.value = _preferences.getString(_currencyKey);
    storyStyle.value = kDebugMode
        ? StoryStyle.parse(_preferences.getString(storyStyleKey))
        : StoryStyle.circle;
  }

  Future<void> saveStoryStyle(StoryStyle style) async {
    if (!kDebugMode) return;
    storyStyle.value = style;
    await _preferences.setString(storyStyleKey, style.name);
  }

  Future<void> saveToken(String token) async {
    await _saveToken(token);
  }

  Future<bool> _saveToken(String token) async {
    // Account currency must not follow a replacement token. App language is
    // retained until the new account confirms its locale via saveUserPresentation.
    final currencyReset = _sessionToken != token
        ? _preferences.remove(_currencyKey)
        : Future.value(true);
    final tokenWrite = _preferences.setString(_token, token);
    _setSession(token);
    final results = await Future.wait([currencyReset, tokenWrite]);
    return results.last;
  }

  Future<String?> getToken() async {
    return _sessionToken;
  }

  Future<void> saveLanguage(String code) async {
    code = effectiveAppLanguage(code);
    language.value = code;
    await _preferences.setString(_languageKey, code);
  }

  String getLanguage() {
    return language.value;
  }

  Future<void> saveCurrency(String? code) async {
    currency.value = code;
    if (code == null) {
      await _preferences.remove(_currencyKey);
      return;
    }
    await _preferences.setString(_currencyKey, code);
  }

  String getCurrency() {
    return currency.value ?? 'EGP';
  }

  /// Apply only a confirmed current account's presentation preferences. Writes
  /// start together before yielding; a later clear/session switch resets them.
  Future<void> saveUserPresentation({
    required String locale,
    required String? currency,
    required int expectedSession,
  }) async {
    if (expectedSession != sessionRevision || !hasSession) return;
    locale = effectiveAppLanguage(locale);
    final writes = [
      _preferences.setString(_languageKey, locale),
      currency == null
          ? _preferences.remove(_currencyKey)
          : _preferences.setString(_currencyKey, currency),
    ];
    language.value = locale;
    if (expectedSession == sessionRevision && hasSession) {
      this.currency.value = currency;
    }
    await Future.wait(writes);
  }

  Future<bool> setString(String key, String value) async {
    if (key == _token) {
      return _saveToken(value);
    }
    return await _preferences.setString(key, value);
  }

  Future<bool> setBool(String key, bool value) async {
    return await _preferences.setBool(key, value);
  }

  String? getString(String key) {
    return _preferences.getString(key);
  }

  bool? getBool(String key) {
    return _preferences.getBool(key);
  }

  Future<void> remove(String key) async {
    final removal = _preferences.remove(key);
    if (key == _token) _setSession(null);
    await removal;
  }

  static const _setupSkippedPrefix = 'profile_setup_skipped_';

  /// Whether account [userId] chose "Skip for now" in Profile Setup. Kept
  /// across logout so that account is not forced back into setup.
  bool isProfileSetupSkipped(String userId) =>
      _preferences.getBool('$_setupSkippedPrefix$userId') ?? false;

  Future<void> markProfileSetupSkipped(String userId) async {
    await _preferences.setBool('$_setupSkippedPrefix$userId', true);
  }

  /// Remove account-scoped values, retaining app language, onboarding,
  /// non-secret push cleanup IDs, per-account setup skips, per-account hidden
  /// chat message IDs and the device-wide notifications soft-ask history.
  /// Removal calls update SharedPreferences' memory synchronously before yielding,
  /// so a later account cannot be cleared by an old session's completion.
  Future<void> clearSession() async {
    final removals = [
      for (final key in _preferences.getKeys())
        if (key != _languageKey &&
            key != onboardingCompletedKey &&
            key != pushDeviceRecordsKey &&
            key != storyStyleKey &&
            !key.startsWith(_setupSkippedPrefix) &&
            !key.startsWith(notificationSoftAskPrefix) &&
            !key.startsWith(chatHiddenMessagesPrefix))
          _preferences.remove(key),
    ];
    _setSession(null);
    // _setSession is a no-op when already signed out.
    if (!hasSession) currency.value = null;
    await Future.wait(removals);
  }

  Future<void> clear() async {
    final clearing = _preferences.clear();
    language.value = 'en';
    currency.value = null;
    storyStyle.value = StoryStyle.circle;
    _setSession(null);
    await clearing;
  }
}
