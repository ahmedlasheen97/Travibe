import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/theme/app_styles.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:travibe/core/widgets/custom_button.dart';
import 'package:travibe/core/widgets/custom_text_field.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';
import 'package:travibe/features/auth/screens/forgetpass/create_new_password_screen.dart';
import 'package:travibe/features/auth/screens/forgetpass/forget_password_screen.dart';
import 'package:travibe/features/auth/screens/forgetpass/reset_new_password_screen.dart';
import 'package:travibe/features/auth/screens/login_screen.dart';
import 'package:travibe/features/auth/screens/otp_verification_screen.dart';
import 'package:travibe/features/auth/widgets/auth_app_bar.dart';
import 'package:travibe/features/auth/widgets/auth_heading.dart';
import 'package:travibe/features/auth/widgets/auth_page.dart';

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

Finder _wrapper(String title) =>
    find.byWidgetPredicate((w) => w is CustomTextField && w.title == title);
Finder _input(String title) =>
    find.descendant(of: _wrapper(title), matching: find.byType(TextFormField));
TextField _field(WidgetTester tester, String title) => tester.widget<TextField>(
  find.descendant(of: _wrapper(title), matching: find.byType(TextField)),
);

List<String> _assets(WidgetTester tester, Finder within) => tester
    .widgetList<SvgPicture>(
      find.descendant(of: within, matching: find.byType(SvgPicture)),
    )
    .map((svg) => (svg.bytesLoader as SvgAssetLoader).assetName)
    .toList();

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

  // OTP keeps a countdown running, so never pumpAndSettle.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> show(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(theme: darkTheme, home: home),
      ),
    );
    await settle(tester);
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  /// Login's main-button height and heading inset, the reference values.
  Future<(double, double)> loginMetrics(WidgetTester tester) async {
    await show(tester, const LoginScreen());
    final metrics = (
      tester.getSize(find.byType(CustomButton)).height,
      tester.getTopLeft(find.text('Hey,\nWelcome Back!')).dx,
    );
    await dispose(tester);
    return metrics;
  }

  final screens = <String, (Widget Function(), String, String)>{
    'Forgot Password': (
      () => const ForgotPasswordScreen(),
      'Forgot your password?',
      'Send Code',
    ),
    'Verify Code': (
      () => const ResetPasswordOtpScreen(email: _email),
      'Verify your email',
      'Verify',
    ),
    'New Password': (
      () => const CreateNewPasswordScreen(email: _email, token: 'local-only'),
      'Create new password',
      'Reset Password',
    ),
    'Verify Email': (
      () => const OtpVerificationScreen(email: _email),
      'Verify your email',
      'Verify',
    ),
  };

  for (final MapEntry(key: name, value: (build, heading, action))
      in screens.entries) {
    testWidgets('$name uses the recovery auth page, title and button', (
      tester,
    ) async {
      final (loginButtonHeight, loginHeadingLeft) = await loginMetrics(tester);
      await show(tester, build());
      expect(find.byType(AuthPage), findsOneWidget);
      expect(tester.widget<AuthPage>(find.byType(AuthPage)).recovery, true);
      // Back button only: no bar title.
      final bar = tester.widget<AuthAppBar>(find.byType(AuthAppBar));
      expect(bar.title, isNull);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byWidgetPredicate((w) => w is Text),
        ),
        findsNothing,
      );
      expect(bar.showBack, true);
      expect(find.byType(BackButtonWidget), findsOneWidget);
      // AppSizes.authRecoveryHeaderGap (40) between the bar and the heading.
      expect(
        tester.getTopLeft(find.text(heading)).dy -
            tester.getBottomLeft(find.byType(AppBar)).dy,
        closeTo(AppSizes.authRecoveryHeaderGap, .01),
      );

      // Smaller centered heading: 20 title, 14 #BDBCBB subtitle.
      final texts = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(AuthHeading),
              matching: find.byType(Text),
            ),
          )
          .toList();
      expect(texts, hasLength(2));
      final (title, subtitle) = (texts[0], texts[1]);
      expect(title.data, heading);
      expect(title.style, AuthHeading.smallTitleStyle);
      expect(
        title.style,
        AppStyles.authTitleStyle.copyWith(fontSize: AppSizes.adaptiveFont(20)),
      );
      expect(subtitle.style!.fontSize, AppSizes.adaptiveFont(14));
      expect(subtitle.style!.color, const Color(0xFFBDBCBB));
      for (final text in texts) {
        expect(text.textAlign, TextAlign.center);
      }
      // Same body inset as Login; the centered text spans the body.
      expect(tester.getTopLeft(find.text(heading)).dx, loginHeadingLeft);
      expect(
        tester.getCenter(find.text(heading)).dx,
        closeTo(tester.getCenter(find.byType(Scaffold)).dx, .01),
      );

      final button = find.widgetWithText(CustomButton, action);
      expect(button, findsOneWidget);
      expect(tester.getSize(button).height, loginButtonHeight);

      // The keyboard never hides the main button: it scrolls into view.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await settle(tester);
      await tester.ensureVisible(button);
      await settle(tester);
      expect(button.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await dispose(tester);
    });
  }

  testWidgets('Forgot Password email field matches Login', (tester) async {
    await show(tester, const ForgotPasswordScreen());
    expect(_assets(tester, _wrapper('Email')), ['assets/images/auth/sms.svg']);
    expect(_field(tester, 'Email').cursorColor, Colors.white);

    await tester.tap(find.text('Send Code'));
    await settle(tester);
    final error = tester.widget<Text>(find.text('Please enter your email'));
    expect(error.style?.color, DarkColors.dangerColor);
    await dispose(tester);
  });

  testWidgets('Create New Password uses the shared password fields', (
    tester,
  ) async {
    await show(
      tester,
      const CreateNewPasswordScreen(email: _email, token: 'local-only'),
    );
    for (final title in ['New Password', 'Confirm Password']) {
      expect(_assets(tester, _wrapper(title)), [
        'assets/images/auth/lock.svg',
        PasswordEye.hidden,
      ]);
      expect(_field(tester, title).obscureText, true);
      expect(_field(tester, title).cursorColor, Colors.white);
    }

    await tester.tap(
      find.descendant(
        of: _wrapper('New Password'),
        matching: find.byType(IconButton),
      ),
    );
    await settle(tester);
    expect(_assets(tester, _wrapper('New Password')).last, PasswordEye.visible);
    expect(_field(tester, 'New Password').obscureText, false);
    expect(_field(tester, 'Confirm Password').obscureText, true);

    await tester.enterText(_input('New Password'), 'short');
    await tester.ensureVisible(find.text('Reset Password'));
    await tester.tap(find.text('Reset Password'));
    await settle(tester);
    final error = tester.widget<Text>(
      find.text('Password must be at least 8 characters'),
    );
    expect(error.style?.color, DarkColors.dangerColor);
    await dispose(tester);
  });

  testWidgets('Password updated! uses the auth title and has no back', (
    tester,
  ) async {
    final (loginButtonHeight, _) = await loginMetrics(tester);
    await show(
      tester,
      CreateNewPasswordScreen(
        email: _email,
        token: 'local-only',
        authRepo: _ResetRepo(),
      ),
    );
    await tester.enterText(_input('New Password'), 'Password1');
    await tester.enterText(_input('Confirm Password'), 'Password1');
    await tester.ensureVisible(find.text('Reset Password'));
    await tester.tap(find.text('Reset Password'));
    await settle(tester);

    final title = tester.widget<Text>(find.text('Password updated!'));
    expect(title.style, AuthHeading.smallTitleStyle);
    expect(title.textAlign, TextAlign.center);
    final bar = tester.widget<AuthAppBar>(find.byType(AuthAppBar));
    expect(bar.showBack, false);
    expect(bar.title, isNull);
    expect(find.byType(BackButtonWidget), findsNothing);
    expect(
      tester.getSize(find.widgetWithText(CustomButton, 'Log In Now')).height,
      loginButtonHeight,
    );
    await dispose(tester);
  });
}
