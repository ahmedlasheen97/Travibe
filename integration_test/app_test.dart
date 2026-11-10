import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/routing/router_generator.dart';
import 'package:travibe/features/auth/screens/login_screen.dart';
import 'package:travibe/features/onboarding/screens/splash_screen.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/main.dart';

import 'support/test_reporting.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerTestReporting(binding);

  testWidgets('signed-out startup reaches Login and password stays private', (
    tester,
  ) async {
    // No device credentials, disk writes, Firebase initialization or API calls.
    // Completed onboarding plus no token takes the local Login startup branch.
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
    final preferences = PreferencesManager();
    await preferences.init();
    final currentUser = CurrentUserCubit();
    final router = RouterGenerator.createRouter();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      await currentUser.close();
    });

    await tester.pumpWidget(MyApp(router: router, currentUser: currentUser));
    expect(SplashScreen.duration, const Duration(milliseconds: 1500));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(preferences.hasSession, isFalse);
    expect(find.byTooltip('Show password'), findsOneWidget);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(find.byTooltip('Hide password'), findsOneWidget);
    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();
    expect(find.byTooltip('Show password'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
