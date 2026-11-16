import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/constants/feature_flags.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/widgets/travibe_toast.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:travibe/core/widgets/custom_button.dart';
import 'package:travibe/features/auth/screens/login_screen.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';
import 'package:travibe/features/auth/screens/sign_up_screen.dart';
import 'package:travibe/features/auth/screens/otp_verification_screen.dart';
import 'package:travibe/features/auth/widgets/auth_app_bar.dart';
import 'package:travibe/features/auth/widgets/custom_or_login_widget.dart';
import 'package:travibe/features/auth/widgets/social_login_button.dart';

import 'auth_glass_ui_test.dart' as glass;
import 'google_auth_test.dart' as google;

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

  Future<void> show(
    WidgetTester tester,
    Widget screen, {
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final signup in [false, true]) {
    testWidgets(
      '${signup ? 'Signup' : 'Login'} hides social controls and centers original text title',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await show(tester, signup ? const SignUpScreen() : const LoginScreen());
        expect(kEnableSocialAuthentication, false);
        expect(find.byType(SocialLoginButton), findsNothing);
        expect(find.byType(CustomOrLoginWidget), findsNothing);
        expect(find.text('Google'), findsNothing);
        expect(find.text('Apple'), findsNothing);
        // Login is the bottom of the auth stack: no back button.
        expect(find.byType(BackButtonWidget), findsNWidgets(signup ? 1 : 0));
        final title = find.descendant(
          of: find.byType(AppBar),
          matching: find.text(signup ? 'Sign Up' : 'Login'),
        );
        expect(title, findsOneWidget);
        expect(tester.getCenter(title).dx, closeTo(195, .01));
        expect(
          tester
              .widget<AuthAppBar>(find.byType(AuthAppBar))
              .preferredSize
              .height,
          kToolbarHeight,
        );
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is SvgPicture &&
                w.bytesLoader is SvgAssetLoader &&
                (w.bytesLoader as SvgAssetLoader).assetName ==
                    'assets/images/interactions/travibe_logo.svg',
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );

    for (final width in [320.0, 375.0, 393.0, 430.0]) {
      testWidgets(
        '${signup ? 'Signup' : 'Login'} stays black on scroll at $width with keyboard and large text',
        (tester) async {
          await show(
            tester,
            signup ? const SignUpScreen() : const LoginScreen(),
            width: width,
            scale: 1.6,
          );
          final bar = tester.widget<AppBar>(find.byType(AppBar));
          expect(bar.scrolledUnderElevation, 0);
          expect(bar.surfaceTintColor, Colors.transparent);
          expect(bar.backgroundColor, DarkColors.backgroundColor);
          final heading = find.text(
            signup ? 'Create\nyour account' : 'Hey,\nWelcome Back!',
          );
          expect(
            tester.getTopLeft(heading).dy -
                tester.getBottomLeft(find.byType(AppBar)).dy,
            closeTo(signup ? 24 : 64, .01),
          );
          expect(
            tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
            DarkColors.backgroundColor,
          );
          await tester.showKeyboard(glass.input('Email'));
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          await tester.pumpAndSettle();
          await tester.drag(
            find.byType(SingleChildScrollView),
            const Offset(0, -800),
          );
          await tester.pumpAndSettle();
          final material = find
              .descendant(
                of: find.byType(AppBar),
                matching: find.byType(Material),
              )
              .first;
          expect(
            tester.widget<Material>(material).color,
            DarkColors.backgroundColor,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'social buttons reject callbacks even if mounted directly in MVP mode',
    (tester) async {
      var calls = 0;
      await show(
        tester,
        Scaffold(
          body: Row(
            children: [
              for (final provider in ['Google', 'Apple'])
                SocialLoginButton(
                  title: provider,
                  iconPath: 'assets/images/auth/${provider.toLowerCase()}.svg',
                  onPressed: () => calls++,
                ),
            ],
          ),
        ),
      );
      for (final button in tester.widgetList<ElevatedButton>(
        find.byType(ElevatedButton),
      )) {
        expect(button.onPressed, isNull);
      }
      await tester.tap(find.text('Google'));
      await tester.tap(find.text('Apple'));
      expect(calls, 0);
    },
  );

  testWidgets(
    'email Login validates then sends existing API fields and keeps verification routing',
    (tester) async {
      final api = google.FakeApi()
        ..handler = () async => google.authJson(verify: true);
      await show(tester, LoginScreen(authRepo: AuthRepo(apiService: api)));
      await tester.tap(find.byType(CustomButton));
      await tester.pumpAndSettle();
      expect(api.calls, isEmpty);
      expect(find.text('Please enter your email'), findsOneWidget);
      await tester.enterText(glass.input('Email'), 'test@example.invalid');
      await tester.enterText(glass.input('Password'), 'Password1');
      await tester.ensureVisible(find.byType(CustomButton));
      await tester.tap(find.byType(CustomButton));
      // The OTP input keeps a cursor animation active; wait for the route only.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(api.calls, ['login']);
      expect(api.body!['email'], 'test@example.invalid');
      expect(api.body!['password'], 'Password1');
      expect(find.byType(OtpVerificationScreen), findsOneWidget);
      expect(await PreferencesManager().getToken(), 'travibe-test-token');
      await tester.pumpWidget(const SizedBox());
    },
  );
  Future<void> submitSignup(WidgetTester tester) async {
    for (final entry in {
      'Email': 'existing@example.invalid',
      'Password': 'Password1',
      'Confirm Password': 'Password1',
    }.entries) {
      await tester.ensureVisible(glass.input(entry.key));
      await tester.enterText(glass.input(entry.key), entry.value);
    }
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.ensureVisible(find.byType(CustomButton));
    await tester.tap(find.byType(CustomButton));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('email Sign Up retains consent, API fields and OTP navigation', (
    tester,
  ) async {
    final api = google.FakeApi()
      ..handler = () async => google.authJson(verify: true);
    await show(tester, SignUpScreen(authRepo: AuthRepo(apiService: api)));
    await submitSignup(tester);
    expect(api.calls, ['register']);
    expect(api.body!['email'], 'existing@example.invalid');
    expect(api.body!['password_confirmation'], 'Password1');
    expect(api.body!['terms_accepted'], true);
    expect(find.byType(OtpVerificationScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Sign Up without consent shows the red toast, not a SnackBar', (
    tester,
  ) async {
    final api = google.FakeApi();
    await show(tester, SignUpScreen(authRepo: AuthRepo(apiService: api)));
    for (final entry in {
      'Email': 'new@example.invalid',
      'Password': 'Password1',
      'Confirm Password': 'Password1',
    }.entries) {
      await tester.ensureVisible(glass.input(entry.key));
      await tester.enterText(glass.input(entry.key), entry.value);
    }
    await tester.ensureVisible(find.byType(CustomButton));
    await tester.tap(find.byType(CustomButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(api.calls, isEmpty);
    final toast = find.byType(TravibeToastView);
    expect(toast, findsOneWidget);
    expect(
      tester.widget<TravibeToastView>(toast).data.variant,
      TravibeToastVariant.error,
    );
    expect(
      find.descendant(
        of: toast,
        matching: find.text('Please accept the Terms & Privacy Policy'),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Login failure toasts the server message, never ApiError{', (
    tester,
  ) async {
    final api = google.FakeApi()
      ..handler = () async => throw ApiError(
        message: 'These credentials do not match our records.',
        statusCode: 422,
      );
    await show(tester, LoginScreen(authRepo: AuthRepo(apiService: api)));
    await tester.enterText(glass.input('Email'), 'test@example.invalid');
    await tester.enterText(glass.input('Password'), 'Password1');
    await tester.ensureVisible(find.byType(CustomButton));
    await tester.tap(find.byType(CustomButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.descendant(
        of: find.byType(TravibeToastView),
        matching: find.text('These credentials do not match our records.'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('ApiError'), findsNothing);
    expect(find.textContaining('unexpected'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  for (final empty in [false, true]) {
    testWidgets(
      'Try Another Email focuses with collapsed cursor (${empty ? 'empty' : 'retained'} email)',
      (tester) async {
        final repo = glass.RegistrationRepo();
        await show(tester, SignUpScreen(authRepo: repo));
        await submitSignup(tester);
        final controller = glass.field(tester, 'Email').controller!;
        if (empty) controller.clear();
        final email = controller.text;
        await tester.tap(find.text('Try Another Email'));
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        expect(controller.text, email);
        expect(
          controller.selection,
          TextSelection.collapsed(offset: email.length),
        );
        expect(glass.field(tester, 'Email').focusNode!.hasFocus, true);
        expect(repo.calls, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
