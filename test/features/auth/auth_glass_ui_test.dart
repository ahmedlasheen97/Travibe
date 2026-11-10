import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:travibe/core/widgets/custom_button.dart';
import 'package:travibe/core/widgets/custom_text_field.dart';
import 'package:travibe/core/routing/router_generator.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';
import 'package:travibe/features/auth/data/auth_response_model.dart';
import 'package:travibe/features/auth/data/registration_error.dart';
import 'package:travibe/features/auth/screens/login_screen.dart';
import 'package:travibe/features/auth/screens/sign_up_screen.dart';
import 'package:travibe/features/auth/widgets/email_exists_dialog.dart';
import 'package:travibe/features/profile/screens/delete_account_screen.dart';
import '../profile/account_deletion_test.dart' as account;

ApiError duplicateEmail() => ApiError(
  message: 'The email has already been taken.',
  statusCode: 422,
  fieldErrors: const {
    'email': ['The email has already been taken.'],
  },
);

class RegistrationRepo extends AuthRepo {
  int calls = 0;
  ApiError failure = duplicateEmail();
  Completer<AuthResponseModel>? gate;
  @override
  Future<AuthResponseModel> register({
    required String email,
    required String password,
    required String passwordConfirmation,
    required bool termsAccepted,
    String? locale,
  }) async {
    calls++;
    if (gate != null) return gate!.future;
    throw failure;
  }
}

Finder wrapper(String title) =>
    find.byWidgetPredicate((w) => w is CustomTextField && w.title == title);
Finder input(String title) =>
    find.descendant(of: wrapper(title), matching: find.byType(TextFormField));
TextField field(WidgetTester tester, String title) => tester.widget<TextField>(
  find.descendant(of: wrapper(title), matching: find.byType(TextField)),
);
Finder eye(String title) =>
    find.descendant(of: wrapper(title), matching: find.byType(IconButton));

String passwordAsset(WidgetTester tester, String title) {
  final svg = tester.widget<SvgPicture>(
    find.descendant(of: eye(title), matching: find.byType(SvgPicture)),
  );
  return (svg.bytesLoader as SvgAssetLoader).assetName;
}

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
  Future<void> show(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(theme: darkTheme, home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    for (final entry in {
      'Email': 'existing@example.invalid',
      'Password': 'Password1',
      'Confirm Password': 'Password1',
    }.entries) {
      await tester.ensureVisible(input(entry.key));
      await tester.pumpAndSettle();
      await tester.enterText(input(entry.key), entry.value);
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.ensureVisible(find.byType(CustomButton));
    await tester.tap(find.byType(CustomButton));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Login toggles SVG visibility, preserves text/cursor/focus/height and accessible actions',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await show(tester, const LoginScreen());
      expect(field(tester, 'Password').obscureText, true);
      expect(
        passwordAsset(tester, 'Password'),
        'assets/images/onboarding/eye-slash.svg',
      );
      expect(find.byTooltip('Show password'), findsOneWidget);
      expect(find.bySemanticsLabel('Show password'), findsOneWidget);
      await tester.enterText(input('Password'), 'Password1');
      final controller = field(tester, 'Password').controller!;
      controller.selection = const TextSelection.collapsed(offset: 3);
      final height = tester.getSize(input('Password')).height;
      expect(tester.getSize(eye('Password')).width, greaterThanOrEqualTo(48));
      await tester.tap(eye('Password'));
      await tester.pump();
      expect(field(tester, 'Password').obscureText, false);
      expect(find.byTooltip('Hide password'), findsOneWidget);
      expect(find.bySemanticsLabel('Hide password'), findsOneWidget);
      expect(controller.text, 'Password1');
      expect(controller.selection.baseOffset, 3);
      expect(field(tester, 'Password').focusNode!.hasFocus, true);
      expect(tester.getSize(input('Password')).height, height);
      final assets = tester
          .widgetList<SvgPicture>(
            find.descendant(
              of: eye('Password'),
              matching: find.byType(SvgPicture),
            ),
          )
          .map((svg) => (svg.bytesLoader as SvgAssetLoader).assetName);
      expect(assets, ['assets/images/interactions/eye.svg']);
      await tester.tap(eye('Password'));
      await tester.pump();
      expect(field(tester, 'Password').obscureText, true);
      expect(
        passwordAsset(tester, 'Password'),
        'assets/images/onboarding/eye-slash.svg',
      );
      expect(controller.text, 'Password1');
      expect(find.byTooltip('Show password'), findsOneWidget);
      semantics.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Sign Up password and confirmation toggle independently without changing values',
    (tester) async {
      await show(tester, const SignUpScreen());
      await tester.enterText(input('Password'), 'Password1');
      await tester.enterText(input('Confirm Password'), 'Different2');
      expect(field(tester, 'Password').obscureText, true);
      expect(
        passwordAsset(tester, 'Password'),
        'assets/images/onboarding/eye-slash.svg',
      );
      expect(field(tester, 'Confirm Password').obscureText, true);
      expect(
        passwordAsset(tester, 'Confirm Password'),
        'assets/images/onboarding/eye-slash.svg',
      );
      await tester.tap(eye('Password'));
      await tester.pump();
      expect(field(tester, 'Password').obscureText, false);
      expect(field(tester, 'Confirm Password').obscureText, true);
      expect(
        passwordAsset(tester, 'Confirm Password'),
        'assets/images/onboarding/eye-slash.svg',
      );
      await tester.tap(eye('Confirm Password'));
      await tester.pump();
      expect(field(tester, 'Confirm Password').obscureText, false);
      expect(
        passwordAsset(tester, 'Confirm Password'),
        'assets/images/interactions/eye.svg',
      );
      expect(field(tester, 'Password').controller!.text, 'Password1');
      expect(field(tester, 'Confirm Password').controller!.text, 'Different2');
      expect(find.byTooltip('Hide password'), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('existing password and confirmation validators remain active', (
    tester,
  ) async {
    final repo = RegistrationRepo();
    await show(tester, SignUpScreen(authRepo: repo));
    await tester.enterText(input('Email'), 'valid@example.invalid');
    await tester.enterText(input('Password'), 'short');
    await tester.enterText(input('Confirm Password'), 'mismatch');
    await tester.ensureVisible(find.byType(CustomButton));
    await tester.tap(find.byType(CustomButton));
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(
      find.text(
        'Password must be at least 8 characters and contain a letter and a number',
      ),
      findsOneWidget,
    );
    expect(repo.calls, 0);
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'duplicate detection requires the exact structured email uniqueness error',
    () {
      expect(isDuplicateEmailError(duplicateEmail()), true);
      for (final error in [
        ApiError(message: 'The email has already been taken.', statusCode: 422),
        ApiError(
          message: 'Invalid',
          statusCode: 422,
          fieldErrors: const {
            'email': ['The email field must be a valid email address.'],
          },
        ),
        ApiError(
          message: 'Invalid',
          statusCode: 422,
          fieldErrors: const {
            'password': ['The email has already been taken.'],
          },
        ),
        ApiError(
          message: 'Invalid',
          statusCode: 500,
          fieldErrors: const {
            'email': ['The email has already been taken.'],
          },
        ),
      ]) {
        expect(isDuplicateEmailError(error), false);
      }
    },
  );
  test(
    'ApiService and AuthRepo retain duplicate email field errors and status',
    () async {
      final harness = account.AccountHarness();
      harness.adapter.handler = (_) async => ResponseBody.fromString(
        jsonEncode({
          'message': 'The email has already been taken.',
          'errors': {
            'email': ['The email has already been taken.'],
          },
        }),
        422,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
      try {
        await AuthRepo(apiService: harness.api).register(
          email: 'existing@example.invalid',
          password: 'Password1',
          passwordConfirmation: 'Password1',
          termsAccepted: true,
        );
        fail('Expected validation error');
      } on ApiError catch (error) {
        expect(error.statusCode, 422);
        expect(error.fieldErrors['email'], [
          'The email has already been taken.',
        ]);
        expect(isDuplicateEmailError(error), true);
      }
    },
  );
  testWidgets(
    'duplicate response opens glass modal with supplied SVG and exact copy; secondary preserves form and focuses email',
    (tester) async {
      final repo = RegistrationRepo();
      await show(tester, SignUpScreen(authRepo: repo));
      await submit(tester);
      expect(repo.calls, 1);
      expect(find.byType(EmailExistsDialog), findsOneWidget);
      expect(find.text('Email already exists'), findsOneWidget);
      expect(
        find.text(
          'An account with this email exists. Please log in or use another email.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('email-exists-glass')), findsOneWidget);
      expect(
        tester
            .widgetList<SvgPicture>(
              find.descendant(
                of: find.byType(EmailExistsDialog),
                matching: find.byType(SvgPicture),
              ),
            )
            .any(
              (svg) =>
                  (svg.bytesLoader as SvgAssetLoader).assetName ==
                  EmailExistsDialog.warningAsset,
            ),
        true,
      );
      await tester.tap(find.text('Try Another Email'));
      await tester.pumpAndSettle();
      expect(find.byType(EmailExistsDialog), findsNothing);
      expect(field(tester, 'Email').focusNode!.hasFocus, true);
      expect(
        field(tester, 'Email').controller!.selection,
        const TextSelection(baseOffset: 0, extentOffset: 24),
      );
      expect(
        field(tester, 'Email').controller!.text,
        'existing@example.invalid',
      );
      expect(field(tester, 'Password').controller!.text, 'Password1');
      expect(field(tester, 'Confirm Password').controller!.text, 'Password1');
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, true);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'other 422 errors keep their message and never show duplicate modal',
    (tester) async {
      final repo = RegistrationRepo()
        ..failure = ApiError(
          message: 'Password is too weak',
          statusCode: 422,
          fieldErrors: const {
            'password': ['Password is too weak'],
          },
        );
      await show(tester, SignUpScreen(authRepo: repo));
      await submit(tester);
      expect(find.byType(EmailExistsDialog), findsNothing);
      expect(find.text('Password is too weak'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Log In Instead prefills email only and leaves no duplicate auth stack',
    (tester) async {
      await show(tester, SignUpScreen(authRepo: RegistrationRepo()));
      await submit(tester);
      await tester.tap(find.text('Log In Instead'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(SignUpScreen), findsNothing);
      expect(
        field(tester, 'Email').controller!.text,
        'existing@example.invalid',
      );
      expect(field(tester, 'Password').controller!.text, isEmpty);
      expect(
        Navigator.of(tester.element(find.byType(LoginScreen))).canPop(),
        false,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final path in ['/register', '/login']) {
    testWidgets(
      'duplicate Login action uses existing router from $path without stacking',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final router = RouterGenerator.createRouter()..go(path);
        await tester.pumpWidget(
          ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, _) =>
                MaterialApp.router(theme: darkTheme, routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();
        final context = tester.element(
          find.byType(path == '/login' ? LoginScreen : SignUpScreen),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => SignUpScreen(authRepo: RegistrationRepo()),
          ),
        );
        await tester.pumpAndSettle();
        await submit(tester);
        await tester.tap(find.text('Log In Instead'));
        await tester.pumpAndSettle();
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(find.byType(SignUpScreen), findsNothing);
        expect(
          field(tester, 'Email').controller!.text,
          'existing@example.invalid',
        );
        expect(field(tester, 'Password').controller!.text, isEmpty);
        expect(
          Navigator.of(tester.element(find.byType(LoginScreen))).canPop(),
          false,
        );
        await tester.pumpWidget(const SizedBox());
        router.dispose();
      },
    );
  }
  testWidgets(
    'repeated submission shares one request and one duplicate dialog',
    (tester) async {
      final repo = RegistrationRepo()..gate = Completer<AuthResponseModel>();
      await show(tester, SignUpScreen(authRepo: repo));
      await submit(tester);
      await tester.tap(find.byType(CustomButton));
      await tester.pump();
      expect(repo.calls, 1);
      repo.gate!.completeError(duplicateEmail());
      await tester.pumpAndSettle();
      expect(find.byType(EmailExistsDialog), findsOneWidget);
      expect(repo.calls, 1);
      await tester.tap(find.text('Try Another Email'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'dialog fits a small screen with keyboard insets and large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(2),
              viewInsets: EdgeInsets.only(bottom: 250),
            ),
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showEmailExistsDialog(context),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(EmailExistsDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Try Another Email'));
      await tester.tap(find.text('Try Another Email'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final screen in [
    const LoginScreen(),
    const SignUpScreen(),
    DeleteAccountScreen(repo: account.MockAccountRepo()),
  ]) {
    testWidgets(
      'shared Back returns from ${screen.runtimeType} to the previous route',
      (tester) async {
        await show(
          tester,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => screen),
                ),
                child: const Text('Open auth'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open auth'));
        await tester.pumpAndSettle();
        expect(find.byType(BackButtonWidget), findsOneWidget);
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(find.text('Open auth'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
