import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/auth/screens/login_screen.dart';
import 'package:travibe/features/auth/screens/sign_up_screen.dart';
import 'package:travibe/features/auth/screens/otp_verification_screen.dart';
import 'package:travibe/features/auth/screens/forgetpass/forget_password_screen.dart';
import 'package:travibe/features/auth/screens/forgetpass/reset_new_password_screen.dart';
import 'package:travibe/features/auth/screens/forgetpass/create_new_password_screen.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
          'Plus Jakarta Sans',
        )..addFont(rootBundle.load('assets/fonts/PlusJakartaSans-Regular.ttf')))
        .load();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
  });
  tearDown(() => PreferencesManager().clear());

  final screens = <String, Widget Function()>{
    'Login': () => const LoginScreen(),
    'Signup': () => const SignUpScreen(),
    'Forgot password': () => const ForgotPasswordScreen(),
    'Reset OTP': () =>
        const ResetPasswordOtpScreen(email: 'test@example.invalid'),
    'New password': () => const CreateNewPasswordScreen(
      email: 'test@example.invalid',
      token: 'local-test-only',
    ),
    'Verification': () =>
        const OtpVerificationScreen(email: 'test@example.invalid'),
  };
  const headings = {
    'Login': 'Hey,\nWelcome Back!',
    'Signup': 'Create\nyour account',
    'Forgot password': 'Forgot your password?',
    'Reset OTP': 'Verify your email',
    'New password': 'Create new password',
    'Verification': 'Verify your email',
  };
  for (final size in const [
    Size(320, 568),
    Size(375, 667),
    Size(390, 844),
    Size(430, 932),
    Size(360, 800),
    Size(844, 390),
  ]) {
    for (final language in ['en', 'ar']) {
      for (final screen in screens.entries) {
        testWidgets(
          '${screen.key} $size $language supports 2x text, keyboard and scrolling',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = size;
            tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
            tester.view.viewPadding = const FakeViewPadding(
              top: 24,
              bottom: 20,
            );
            addTearDown(tester.view.reset);
            await tester.pumpWidget(
              ScreenUtilInit(
                designSize: const Size(390, 844),
                minTextAdapt: true,
                splitScreenMode: true,
                builder: (_, _) => MaterialApp(
                  theme: darkTheme,
                  locale: Locale(language),
                  supportedLocales: const [Locale('en'), Locale('ar')],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(2)),
                    child: child!,
                  ),
                  home: screen.value(),
                ),
              ),
            );
            // OTP cursors continue to blink, so don't wait for all animations.
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 500));
            expect(tester.takeException(), isNull);
            final scroll = find.byType(SingleChildScrollView).first;
            expect(
              Directionality.of(tester.element(scroll)),
              language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
            );
            final headingText = headings[screen.key];
            if (headingText != null) {
              final heading = find.text(headingText);
              final gap =
                  tester.getTopLeft(heading).dy -
                  tester.getBottomLeft(find.byType(AppBar)).dy;
              // Login/Sign Up: 24 under the titled bar, 32 start-aligned title.
              // Recovery/verify: 40 under a back-only bar, 20 centered title.
              final big = screen.key == 'Login' || screen.key == 'Signup';
              final gapSize = big ? 24 : 40;
              expect(
                gap,
                inInclusiveRange(gapSize * .85 - .01, gapSize * 1.15 + .01),
              );
              final text = tester.widget<Text>(heading);
              final style = text.style!;
              expect(style.fontWeight, FontWeight.w700);
              expect(style.height, 1.25);
              final size = big ? 32 : 20;
              expect(style.fontSize, inInclusiveRange(size * .9, size * 1.1));
              expect(text.textAlign, big ? TextAlign.start : TextAlign.center);
              // Same horizontal inset as Login/Sign Up (adaptiveWidth(8));
              // centered headings span the body, so both edges are inset.
              final scrollLeft = tester.getTopLeft(scroll).dx;
              final scrollRight = tester.getTopRight(scroll).dx;
              final inset = language == 'ar'
                  ? scrollRight - tester.getTopRight(heading).dx
                  : tester.getTopLeft(heading).dx - scrollLeft;
              expect(inset, inInclusiveRange(8 * .85 - .01, 8 * 1.15 + .01));
              if (!big) {
                expect(
                  tester.getCenter(heading).dx,
                  closeTo(tester.getCenter(scroll).dx, .01),
                );
              }
            }
            tester.view.viewInsets = const FakeViewPadding(bottom: 270);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 500));
            expect(tester.takeException(), isNull);
            await tester.drag(scroll, const Offset(0, -1800));
            await tester.pump(const Duration(milliseconds: 500));
            expect(tester.takeException(), isNull);
            // Dispose focused editors/timers before resetting window metrics.
            await tester.pumpWidget(const SizedBox());
            await tester.pump();
          },
        );
      }
    }
  }
}
