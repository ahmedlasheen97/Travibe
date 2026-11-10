import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';

void main() {
  final preferences = PreferencesManager();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });
  tearDown(() => preferences.clear());

  test(
    'missing onboarding flag is false, completion persists across init',
    () async {
      expect(preferences.onboardingCompleted, false);
      await preferences.completeOnboarding();
      expect(preferences.getBool('onboarding_completed'), true);
      await preferences.init();
      expect(preferences.onboardingCompleted, true);
    },
  );
  test(
    'clearSession preserves only language and onboarding, removes account values',
    () async {
      await preferences.completeOnboarding();
      await preferences.saveLanguage('ar');
      await preferences.saveToken('token');
      await preferences.saveCurrency('AED');
      await preferences.setBool('account_flag', true);
      await preferences.setString('private_history', 'private');
      final before = preferences.sessionRevision;
      await preferences.clearSession();
      expect(preferences.onboardingCompleted, true);
      expect(preferences.language.value, 'ar');
      expect(preferences.getString('selected_language'), 'ar');
      expect(preferences.hasSession, false);
      expect(await preferences.getToken(), isNull);
      expect(preferences.getString('_token'), isNull);
      expect(preferences.currency.value, isNull);
      expect(preferences.getString('selected_currency'), isNull);
      expect(preferences.getBool('account_flag'), isNull);
      expect(preferences.getString('private_history'), isNull);
      expect(preferences.sessionRevision, before + 1);
    },
  );
  test(
    'token changes preserve chosen language and reset account currency',
    () async {
      await preferences.saveLanguage('ar');
      await preferences.saveToken('first');
      expect(preferences.language.value, 'ar');
      await preferences.saveCurrency('USD');
      final revision = preferences.sessionRevision;
      var notifications = 0;
      void listener() => notifications++;
      preferences.addListener(listener);
      addTearDown(() => preferences.removeListener(listener));
      await preferences.saveToken('first');
      expect(preferences.sessionRevision, revision);
      expect(preferences.currency.value, 'USD');
      await preferences.setString('_token', 'replacement');
      expect(preferences.sessionRevision, revision + 1);
      expect(notifications, 1);
      expect(preferences.getString('selected_currency'), isNull);
      expect(preferences.language.value, 'ar');
      await preferences.completeOnboarding();
      expect(notifications, 1);
    },
  );
  test(
    'only current account can apply confirmed locale and currency',
    () async {
      await preferences.saveLanguage('ar');
      await preferences.saveToken('first');
      final first = preferences.sessionRevision;
      await preferences.saveToken('second');
      await preferences.saveUserPresentation(
        locale: 'en',
        currency: 'USD',
        expectedSession: first,
      );
      expect(preferences.language.value, 'ar');
      expect(preferences.currency.value, isNull);
      await preferences.saveUserPresentation(
        locale: 'en',
        currency: 'EUR',
        expectedSession: preferences.sessionRevision,
      );
      expect(preferences.language.value, 'en');
      expect(preferences.currency.value, 'EUR');
    },
  );
  test(
    'late clear completion cannot remove a new session or its currency',
    () async {
      await preferences.saveToken('old');
      final clearing = preferences.clearSession();
      await preferences.saveToken('new');
      await preferences.saveCurrency('EUR');
      await clearing;
      expect(await preferences.getToken(), 'new');
      expect(preferences.getString('_token'), 'new');
      expect(preferences.getString('selected_currency'), 'EUR');
    },
  );
  test(
    'synchronous session listeners cannot leave an older persisted token',
    () async {
      void replace() {
        if (preferences.hasSession &&
            preferences.getString('_token') == 'old') {
          preferences.saveToken('new');
        }
      }

      preferences.addListener(replace);
      addTearDown(() => preferences.removeListener(replace));
      await preferences.saveToken('old');
      expect(await preferences.getToken(), 'new');
      expect(preferences.getString('_token'), 'new');
    },
  );
  test(
    'replacement login from logout notification survives all old removals',
    () async {
      await preferences.saveToken('old');
      void replace() {
        if (!preferences.hasSession) preferences.saveToken('new');
      }

      preferences.addListener(replace);
      await preferences.clearSession();
      preferences.removeListener(replace);
      expect(await preferences.getToken(), 'new');
      expect(preferences.getString('_token'), 'new');
    },
  );
  test(
    'full clear still resets onboarding, app language, and currency',
    () async {
      await preferences.completeOnboarding();
      await preferences.saveLanguage('ar');
      await preferences.clear();
      expect(preferences.onboardingCompleted, false);
      expect(preferences.language.value, 'en');
      expect(preferences.currency.value, isNull);
    },
  );
}
