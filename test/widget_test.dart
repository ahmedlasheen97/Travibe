import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/routing/router_generator.dart';
import 'package:travibe/features/auth/screens/login_screen.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts = FontLoader('Plus Jakarta Sans')
      ..addFont(rootBundle.load('assets/fonts/PlusJakartaSans-Regular.ttf'));
    await fonts.load();
  });
  testWidgets('signed-out app startup opens Login without a backend', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Replace the unused Flutter counter-template assumptions with real startup.
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
    await PreferencesManager().init();
    final currentUser = CurrentUserCubit();
    final router = RouterGenerator.createRouter();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      await currentUser.close();
    });
    await tester.pumpWidget(MyApp(currentUser: currentUser, router: router));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byTooltip('Show password'), findsOneWidget);
    expect(PreferencesManager().hasSession, isFalse);
    expect(tester.takeException(), isNull);
  });
}
