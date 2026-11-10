import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/main.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/notifications/push_notification_service.dart';
import 'package:travibe/core/routing/router_generator.dart';
import 'package:travibe/features/onboarding/screens/splash_screen.dart';
import 'package:travibe/features/onboarding/screens/onboarding_screen.dart';
import '../../core/notifications/push_fakes.dart';
import 'onboarding_fixtures.dart';

void main() {
  testWidgets(
    'unavailable Messaging does not block splash or API-driven onboarding',
    (tester) async {
      final prefs = PreferencesManager();
      SharedPreferences.setMockInitialValues({});
      await prefs.init();
      final client = FakeMessagingClient()..available = false;
      final push = PushNotificationService(client: client);
      final repo = FakeOnboardingRepo();
      final router = RouterGenerator.createRouter(onboardingRepo: repo);
      await tester.pumpWidget(MyApp(router: router, pushNotifications: push));
      await tester.runAsync(
        () => Future.wait([
          const SvgAssetLoader(SplashScreen.symbolAsset).loadBytes(null),
          const SvgAssetLoader(SplashScreen.wordmarkAsset).loadBytes(null),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text('Discover places from the server'), findsOneWidget);
      expect(client.starts, 1);
      expect(push.supported, false);
      expect(prefs.onboardingCompleted, false);
      expect(prefs.hasSession, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      push.dispose();
      await client.close();
      await prefs.clear();
    },
  );
}
