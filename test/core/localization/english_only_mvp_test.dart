import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/constants/app_languages.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/notifications/push_notification_service.dart';
import 'package:travibe/core/routing/router_generator.dart';
import 'package:travibe/features/auth/screens/login_screen.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/widgets/language_bottom_sheet.dart';
import 'package:travibe/main.dart';

import '../notifications/push_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts = FontLoader('Plus Jakarta Sans')
      ..addFont(rootBundle.load('assets/fonts/PlusJakartaSans-Regular.ttf'));
    await fonts.load();
  });

  test('Arabic is off for the MVP; Arabic codes fall back to English', () {
    expect(kArabicEnabled, isFalse);
    expect(kAppLanguageCodes, {'en'});
    expect(effectiveAppLanguage('ar'), 'en');
    expect(effectiveAppLanguage(null), 'en');
    expect(effectiveAppLanguage('en'), 'en');
  });

  test('a previously saved Arabic choice loads as English', () async {
    SharedPreferences.setMockInitialValues({'selected_language': 'ar'});
    final preferences = PreferencesManager();
    await preferences.init();
    addTearDown(preferences.clear);
    expect(preferences.getLanguage(), 'en');
    await preferences.saveLanguage('ar');
    expect(preferences.getLanguage(), 'en');
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    Map<String, Object> saved = const {},
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.localesTestValue = const [Locale('ar', 'EG')];
    tester.platformDispatcher.localeTestValue = const Locale('ar', 'EG');
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    SharedPreferences.setMockInitialValues({
      'onboarding_completed': true,
      ...saved,
    });
    await PreferencesManager().init();
    final currentUser = CurrentUserCubit();
    final router = RouterGenerator.createRouter();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      await currentUser.close();
    });
    final push = PushNotificationService(
      client: FakeMessagingClient()..available = false,
    );
    await tester.pumpWidget(
      MyApp(currentUser: currentUser, router: router, pushNotifications: push),
    );
    await tester.pumpAndSettle();
  }

  void expectEnglishLtr(WidgetTester tester) {
    final context = tester.element(find.byType(LoginScreen));
    expect(Localizations.localeOf(context).languageCode, 'en');
    expect(Directionality.of(context), TextDirection.ltr);
  }

  testWidgets('an Arabic-locale phone still gets English LTR', (tester) async {
    await pumpApp(tester);
    expect(
      tester.binding.platformDispatcher.locale.languageCode,
      'ar',
      reason: 'the simulated phone must really be Arabic',
    );
    expectEnglishLtr(tester);
  });

  testWidgets('saved Arabic on an Arabic phone still gets English LTR', (
    tester,
  ) async {
    await pumpApp(tester, saved: {'selected_language': 'ar'});
    expectEnglishLtr(tester);
  });

  testWidgets('the Language sheet offers only English', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => LanguageBottomSheet.show(context, 'ar'),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(LanguageBottomSheet), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('العربية'), findsNothing);
    // A stale Arabic selection is shown as English.
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });
}
