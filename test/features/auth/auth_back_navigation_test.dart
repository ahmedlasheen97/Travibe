import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/routing/app_routes.dart';
import 'package:travibe/core/routing/router_generator.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:travibe/core/widgets/custom_button.dart';
import 'package:travibe/core/widgets/custom_text_field.dart';
import 'package:travibe/core/widgets/glass_confirm_dialog.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';
import 'package:travibe/features/auth/data/auth_response_model.dart';
import 'package:travibe/features/auth/data/user_model.dart';
import 'package:travibe/features/auth/screens/auth_navigation.dart';
import 'package:travibe/features/auth/screens/forgetpass/create_new_password_screen.dart';
import 'package:travibe/features/auth/screens/forgetpass/forget_password_screen.dart';
import 'package:travibe/features/auth/screens/forgetpass/reset_new_password_screen.dart';
import 'package:travibe/features/auth/screens/login_screen.dart';
import 'package:travibe/features/auth/screens/otp_verification_screen.dart';
import 'package:travibe/features/auth/screens/sign_up_screen.dart';

/// Registers successfully with email verification still required.
class VerifyingRepo extends AuthRepo {
  @override
  Future<AuthResponseModel> register({
    required String email,
    required String password,
    required String passwordConfirmation,
    required bool termsAccepted,
    String? locale,
  }) async => AuthResponseModel(
    token: 'local-test-only',
    tokenType: 'Bearer',
    expiresAt: '',
    emailVerificationRequired: true,
    user: UserModel(
      id: '1',
      name: '',
      email: email,
      isFollowing: false,
      followersCount: 0,
      followingCount: 0,
    ),
  );
}

class ResetRepo extends AuthRepo {
  @override
  Future<void> resetPassword({
    required String token,
    required String email,
    required String password,
    required String passwordConfirmation,
  }) async {}
}

const email = 'traveler@example.invalid';

Finder input(String title) => find.descendant(
  of: find.byWidgetPredicate((w) => w is CustomTextField && w.title == title),
  matching: find.byType(TextFormField),
);

bool canPop(WidgetTester tester, Type screen) =>
    Navigator.of(tester.element(find.byType(screen))).canPop();

Future<void> systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await settle(tester);
}

Future<void> tapBack(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Back'));
  await settle(tester);
}

/// Whether the iOS edge swipe can pop [screen]'s route. Flutter's Cupertino
/// transition (used by Material routes on iOS) enables the swipe exactly when
/// `popGestureEnabled` is true; a `PopScope(canPop: false)` turns it off, and a
/// router page without a Material transition never offers it.
bool iosSwipeBack(WidgetTester tester, Type screen) {
  final route = ModalRoute.of(tester.element(find.byType(screen)));
  return route is PageRoute &&
      route is MaterialRouteTransitionMixin &&
      route.popGestureEnabled;
}

/// OTP screens run a resend countdown, so pumpAndSettle would never return.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final preferences = PreferencesManager();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });
  tearDown(() => preferences.clear());

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> show(WidgetTester tester, Widget home) async {
    phone(tester);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(theme: darkTheme, home: home),
      ),
    );
    await settle(tester);
  }

  Future<void> showRouter(WidgetTester tester, String location) async {
    phone(tester);
    final router = RouterGenerator.createRouter()..go(location);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) =>
            MaterialApp.router(theme: darkTheme, routerConfig: router),
      ),
    );
    await settle(tester);
  }

  Future<void> submitSignup(WidgetTester tester) async {
    for (final entry in {
      'Email': email,
      'Password': 'Password1',
      'Confirm Password': 'Password1',
    }.entries) {
      await tester.ensureVisible(input(entry.key));
      await tester.enterText(input(entry.key), entry.value);
      await settle(tester);
    }
    await tester.ensureVisible(find.byType(Checkbox));
    if (tester.widget<Checkbox>(find.byType(Checkbox)).value != true) {
      await tester.tap(find.byType(Checkbox));
    }
    await tester.ensureVisible(find.byType(CustomButton));
    await tester.tap(find.byType(CustomButton));
    await settle(tester);
  }

  group('Login', () {
    testWidgets('has no back button and is the bottom of the auth stack', (
      tester,
    ) async {
      await showRouter(tester, AppRoutes.login);
      expect(find.byType(BackButtonWidget), findsNothing);
      expect(find.byType(BackButton), findsNothing);
      expect(canPop(tester, LoginScreen), false);
      // Not intercepted: Android back is left to close the app.
      expect(
        ModalRoute.of(tester.element(find.byType(LoginScreen)))!.popDisposition,
        RoutePopDisposition.bubble,
      );
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Signup', () {
    testWidgets('route opens above Login; button and Android back go to it', (
      tester,
    ) async {
      for (final back in [tapBack, systemBack]) {
        await showRouter(tester, AppRoutes.register);
        expect(find.byType(SignUpScreen), findsOneWidget);
        expect(canPop(tester, SignUpScreen), true);
        await back(tester);
        expect(find.byType(SignUpScreen), findsNothing);
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(canPop(tester, LoginScreen), false);
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('iOS swipe is enabled and Login is beneath', (tester) async {
      await showRouter(tester, AppRoutes.register);
      expect(iosSwipeBack(tester, SignUpScreen), true);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('as the only route, back still leads to Login', (tester) async {
      for (final back in [tapBack, systemBack]) {
        await show(tester, const SignUpScreen());
        await back(tester);
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(canPop(tester, LoginScreen), false);
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Login and Signup links never stack a second Login', (
      tester,
    ) async {
      await show(tester, const LoginScreen());
      await tester.ensureVisible(find.text('Sign Up'));
      await tester.tap(find.text('Sign Up'));
      await settle(tester);
      expect(canPop(tester, SignUpScreen), true);
      await tester.ensureVisible(find.text('Login').last);
      await tester.tap(find.text('Login').last);
      await settle(tester);
      expect(find.byType(SignUpScreen), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(canPop(tester, LoginScreen), false);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('OTP', () {
    testWidgets('button and Android back return to Signup with the email', (
      tester,
    ) async {
      await show(tester, SignUpScreen(authRepo: VerifyingRepo()));
      for (final back in [tapBack, systemBack]) {
        await submitSignup(tester);
        expect(find.byType(OtpVerificationScreen), findsOneWidget);
        await back(tester);
        expect(find.byType(OtpVerificationScreen), findsNothing);
        expect(find.byType(SignUpScreen), findsOneWidget);
        expect(find.text(email), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('iOS swipe is enabled above Signup', (tester) async {
      await show(tester, SignUpScreen(authRepo: VerifyingRepo()));
      await submitSignup(tester);
      expect(iosSwipeBack(tester, OtpVerificationScreen), true);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('opened at startup, back rebuilds Signup above Login', (
      tester,
    ) async {
      for (final back in [tapBack, systemBack]) {
        await showRouter(
          tester,
          Uri(
            path: AppRoutes.otpVerification,
            queryParameters: {'email': email},
          ).toString(),
        );
        expect(canPop(tester, OtpVerificationScreen), false);
        await back(tester);
        expect(find.byType(OtpVerificationScreen), findsNothing);
        expect(find.byType(SignUpScreen), findsOneWidget);
        expect(find.text(email), findsOneWidget);
        expect(canPop(tester, SignUpScreen), true);
      }
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Forgot password', () {
    testWidgets('back returns to Login; "Log In" does not stack Login', (
      tester,
    ) async {
      await show(tester, const LoginScreen());
      for (final leave in <Future<void> Function(WidgetTester)>[
        tapBack,
        systemBack,
        (tester) async {
          await tester.ensureVisible(find.text('Log In'));
          await tester.tap(find.text('Log In'));
          await settle(tester);
        },
      ]) {
        await tester.tap(find.text('Forgot Password?'));
        await settle(tester);
        expect(find.byType(ForgotPasswordScreen), findsOneWidget);
        await leave(tester);
        expect(find.byType(ForgotPasswordScreen), findsNothing);
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(canPop(tester, LoginScreen), false);
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('reset code back returns to Forgot password with the email', (
      tester,
    ) async {
      await show(tester, const ForgotPasswordScreen());
      await tester.enterText(input('Email'), email);
      Navigator.of(tester.element(find.byType(ForgotPasswordScreen))).push(
        MaterialPageRoute<void>(
          builder: (_) => const ResetPasswordOtpScreen(email: email),
        ),
      );
      await settle(tester);
      await tapBack(tester);
      expect(find.byType(ResetPasswordOtpScreen), findsNothing);
      expect(find.text(email), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Create new password', () {
    Future<void> open(WidgetTester tester, {AuthRepo? repo}) async {
      // Mirrors the real stack: Login → Forgot → reset code → new password.
      await show(tester, const LoginScreen());
      final navigator = Navigator.of(tester.element(find.byType(LoginScreen)));
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => const ForgotPasswordScreen()),
      );
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const ResetPasswordOtpScreen(email: email),
        ),
      );
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => CreateNewPasswordScreen(
            email: email,
            token: 'local-test-only',
            authRepo: repo,
          ),
        ),
      );
      await settle(tester);
    }

    void expectOnlyLogin(WidgetTester tester) {
      expect(find.byType(CreateNewPasswordScreen), findsNothing);
      expect(find.byType(ResetPasswordOtpScreen), findsNothing);
      expect(find.byType(ForgotPasswordScreen), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text(email), findsOneWidget);
      expect(canPop(tester, LoginScreen), false);
    }

    testWidgets('back asks to cancel the reset and never returns to OTP', (
      tester,
    ) async {
      for (final back in [tapBack, systemBack]) {
        await open(tester);
        await back(tester);
        expect(find.byType(GlassConfirmDialog), findsOneWidget);
        expect(find.text('Cancel password reset?'), findsOneWidget);
        await tester.tap(find.text('Continue'));
        await settle(tester);
        expect(find.byType(CreateNewPasswordScreen), findsOneWidget);
        await back(tester);
        await tester.tap(find.text('Cancel reset'));
        await settle(tester);
        expectOnlyLogin(tester);
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('iOS swipe is disabled so it cannot skip the confirm', (
      tester,
    ) async {
      await open(tester);
      expect(iosSwipeBack(tester, CreateNewPasswordScreen), false);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('after success: no back button, Android back goes to Login', (
      tester,
    ) async {
      await open(tester, repo: ResetRepo());
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Password1');
      await tester.enterText(fields.at(1), 'Password1');
      await tester.ensureVisible(find.text('Reset Password'));
      await tester.tap(find.text('Reset Password'));
      await settle(tester);
      expect(find.text('Password updated!'), findsOneWidget);
      expect(find.byType(BackButtonWidget), findsNothing);
      await systemBack(tester);
      expect(find.byType(GlassConfirmDialog), findsNothing);
      expectOnlyLogin(tester);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('a completed auth step clears every route beneath it', (
    tester,
  ) async {
    await show(tester, const LoginScreen());
    final context = tester.element(find.byType(LoginScreen));
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SignUpScreen()));
    await settle(tester);
    AuthNavigation.resetTo(
      tester.element(find.byType(SignUpScreen)),
      (_) => const Scaffold(body: Text('Home')),
    );
    await settle(tester);
    expect(find.text('Home'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(SignUpScreen), findsNothing);
    expect(Navigator.of(tester.element(find.text('Home'))).canPop(), false);
    await tester.pumpWidget(const SizedBox());
  });
}
