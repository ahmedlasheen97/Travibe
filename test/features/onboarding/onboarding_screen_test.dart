import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/auth/screens/sign_up_screen.dart';
import 'package:travibe/features/onboarding/data/models/onboarding_model.dart';
import 'package:travibe/features/onboarding/screens/onboarding_screen.dart';
import 'onboarding_fixtures.dart';

void main() {
  final preferences = PreferencesManager();
  setUpAll(() async {
    final fonts = FontLoader('Plus Jakarta Sans')
      ..addFont(rootBundle.load('assets/fonts/PlusJakartaSans-Regular.ttf'));
    await fonts.load();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });
  tearDown(() => preferences.clear());

  Future<void> show(
    WidgetTester tester,
    FakeOnboardingRepo repo, {
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => ValueListenableBuilder<String>(
          valueListenable: preferences.language,
          builder: (_, code, _) => MaterialApp(
            theme: darkTheme,
            locale: Locale(code),
            supportedLocales: const [Locale('en'), Locale('ar')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: OnboardingScreen(repo: repo),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets('viewing or interrupting onboarding does not complete it', (
    tester,
  ) async {
    await show(tester, FakeOnboardingRepo());
    expect(find.text('Discover places from the server'), findsOneWidget);
    expect(preferences.onboardingCompleted, false);
    await tester.ensureVisible(find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(preferences.onboardingCompleted, false);
    await tester.pumpWidget(const SizedBox());
    await preferences.init();
    expect(preferences.onboardingCompleted, false);
  });
  testWidgets(
    'explicit skip persists completion and replaces onboarding with Sign Up',
    (tester) async {
      await show(tester, FakeOnboardingRepo());
      await tester.ensureVisible(find.text('Skip'));
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(preferences.onboardingCompleted, true);
      expect(find.byType(SignUpScreen), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(
        Navigator.of(tester.element(find.byType(SignUpScreen))).canPop(),
        false,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'finishing last backend slide persists completion and opens Sign Up',
    (tester) async {
      await show(tester, FakeOnboardingRepo());
      for (var i = 0; i < 2; i++) {
        await tester.ensureVisible(find.text('Next'));
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(preferences.onboardingCompleted, false);
      }
      await tester.ensureVisible(find.text('Get Started'));
      await tester.drag(
        find.byIcon(Icons.arrow_forward_ios),
        const Offset(320, 0),
      );
      await tester.pumpAndSettle();
      expect(preferences.onboardingCompleted, true);
      expect(find.byType(SignUpScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'backend languages save selection, reload copy and retain Arabic RTL',
    (tester) async {
      final repo = FakeOnboardingRepo();
      await show(tester, repo);
      await tester.tap(find.byIcon(Icons.language));
      await tester.pumpAndSettle();
      expect(find.text('English'), findsOneWidget);
      expect(find.text('العربية'), findsOneWidget);
      await tester.tap(find.text('العربية'));
      await tester.pumpAndSettle();
      expect(preferences.getLanguage(), 'ar');
      expect(repo.requestedLocales.last, 'ar');
      expect(
        Directionality.of(tester.element(find.byType(PageView))),
        TextDirection.rtl,
      );
      expect(find.text('AR'), findsOneWidget);
      await preferences.saveToken('new-auth-token');
      await tester.pumpAndSettle();
      expect(preferences.getLanguage(), 'ar');
      expect(preferences.onboardingCompleted, false);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'API failure offers retry and explicit skip without automatic completion',
    (tester) async {
      final repo = FakeOnboardingRepo()..failure = StateError('offline');
      await show(tester, repo);
      expect(find.text('Unable to load onboarding.'), findsOneWidget);
      expect(preferences.onboardingCompleted, false);
      repo.failure = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Discover places from the server'), findsOneWidget);
      expect(preferences.onboardingCompleted, false);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('pending backend content does not mark completion', (
    tester,
  ) async {
    final gate = Completer<List<OnboardingModel>>();
    final repo = FakeOnboardingRepo()..gate = gate;
    await show(tester, repo, settle: false);
    expect(preferences.onboardingCompleted, false);
    await tester.pumpWidget(const SizedBox());
    gate.complete(OnboardingModel.parse(slideJson()));
    await tester.pump();
    expect(preferences.onboardingCompleted, false);
  });
  testWidgets(
    'skip from an API error persists completion and opens existing Sign Up',
    (tester) async {
      await show(tester, FakeOnboardingRepo()..failure = StateError('offline'));
      expect(find.text('Unable to load onboarding.'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.byType(SignUpScreen), findsOneWidget);
      expect(preferences.onboardingCompleted, true);
      expect(preferences.hasSession, false);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
