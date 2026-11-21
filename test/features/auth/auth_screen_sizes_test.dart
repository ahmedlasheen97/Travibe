import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/custom_button.dart';
import 'package:travibe/core/widgets/custom_text_field.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';
import 'package:travibe/features/auth/screens/forgetpass/create_new_password_screen.dart';
import 'package:travibe/features/auth/screens/forgetpass/forget_password_screen.dart';
import 'package:travibe/features/auth/screens/forgetpass/reset_new_password_screen.dart';
import 'package:travibe/features/auth/screens/login_screen.dart';
import 'package:travibe/features/auth/screens/otp_verification_screen.dart';
import 'package:travibe/features/auth/screens/sign_up_screen.dart';
import 'package:travibe/features/auth/widgets/auth_app_bar.dart';

const _email = 'traveler@example.invalid';

class _ResetRepo extends AuthRepo {
  @override
  Future<void> resetPassword({
    required String token,
    required String email,
    required String password,
    required String passwordConfirmation,
  }) async {}
}

Finder _input(String title) => find.descendant(
  of: find.byWidgetPredicate((w) => w is CustomTextField && w.title == title),
  matching: find.byType(TextFormField),
);

/// Small, normal and large phones, plain text scale and real safe areas.
void main() {
  setUpAll(() async {
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      await (FontLoader('Plus Jakarta Sans')..addFont(
            rootBundle.load('assets/fonts/PlusJakartaSans-$weight.ttf'),
          ))
          .load();
    }
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
  });
  tearDown(() => PreferencesManager().clear());

  // OTP screens run a countdown, so never pumpAndSettle.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Name → (screen, main button, top bar title, reach the screen's state).
  final screens =
      <
        String,
        (
          Widget Function(),
          String,
          String?,
          Future<void> Function(WidgetTester)?,
        )
      >{
        'Login': (() => const LoginScreen(), 'Login', 'Login', null),
        'Sign Up': (() => const SignUpScreen(), 'Sign Up', 'Sign Up', null),
        'Verify Email': (
          () => const OtpVerificationScreen(email: _email),
          'Verify',
          null,
          null,
        ),
        'Forgot Password': (
          () => const ForgotPasswordScreen(),
          'Send Code',
          null,
          null,
        ),
        'Verify Code': (
          () => const ResetPasswordOtpScreen(email: _email),
          'Verify',
          null,
          null,
        ),
        'New Password': (
          () => const CreateNewPasswordScreen(email: _email, token: 'local'),
          'Reset Password',
          null,
          null,
        ),
        'Password updated!': (
          () => CreateNewPasswordScreen(
            email: _email,
            token: 'local',
            authRepo: _ResetRepo(),
          ),
          'Log In Now',
          null,
          (tester) async {
            await tester.enterText(_input('New Password'), 'Password1');
            await tester.enterText(_input('Confirm Password'), 'Password1');
            await tester.ensureVisible(find.text('Reset Password'));
            await tester.tap(find.text('Reset Password'));
            await settle(tester);
            expect(find.text('Password updated!'), findsOneWidget);
          },
        ),
      };

  for (final size in const [Size(375, 667), Size(390, 844), Size(430, 932)]) {
    for (final MapEntry(key: name, value: (build, action, barTitle, reach))
        in screens.entries) {
      testWidgets('$name $size: no overflow, button reachable with keyboard', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ScreenUtilInit(
            designSize: const Size(390, 844),
            minTextAdapt: true,
            splitScreenMode: true,
            builder: (_, _) => MaterialApp(theme: darkTheme, home: build()),
          ),
        );
        await settle(tester);
        await reach?.call(tester);
        expect(tester.takeException(), isNull);
        expect(
          tester.widget<AuthAppBar>(find.byType(AuthAppBar)).title,
          barTitle,
        );

        final button = find.widgetWithText(CustomButton, action);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await settle(tester);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(button);
        await settle(tester);
        expect(button.hitTestable(), findsOneWidget);
        final bottom = tester.getBottomLeft(button).dy;
        expect(bottom, lessThanOrEqualTo(size.height - 300 + .01));
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
    }
  }
}
