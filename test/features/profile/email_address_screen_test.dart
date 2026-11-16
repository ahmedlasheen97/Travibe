import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/glass_confirm_dialog.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';
import 'package:travibe/features/auth/screens/otp_verification_screen.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/data/profile_repo.dart';
import 'package:travibe/features/profile/data/settings_repo.dart';
import 'package:travibe/features/profile/screens/email_address_screen.dart';
import 'package:travibe/features/profile/screens/settings_screen.dart';

import 'fixtures.dart' as fx;
import 'settings_privacy_test.dart' show settingsUser;

/// The OTP pin cursor blinks forever, so pumpAndSettle never settles there.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const _current = 'Salma.travels21@gmail.com';

class _EmailApi extends ApiService {
  _EmailApi({bool verified = true}) {
    user = {
      ...fx.profileJson(),
      ...settingsUser(),
      'email': _current,
      'email_verified_at': verified ? '2026-01-02T10:00:00Z' : null,
    };
  }

  late Map<String, dynamic> user;
  final posts = <(String, Map<String, dynamic>)>[];

  /// Next results for `email/change`, consumed in order (null = 202).
  final changeResults = <Object?>[];
  Object? verifyError;

  @override
  Future<bool> revokeCurrentToken() async => true;

  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async => {'data': Map<String, dynamic>.from(user)};

  @override
  Future<dynamic> post(String endpoint, Map<String, dynamic> data) async {
    posts.add((endpoint, Map.of(data)));
    switch (endpoint) {
      case 'email/change':
        final result = changeResults.isEmpty ? null : changeResults.removeAt(0);
        if (result is ApiError) throw result;
        return {'message': 'Verification code sent.', 'email': data['email']};
      case 'email/change/verify':
        if (verifyError case final ApiError error) throw error;
        user = {
          ...user,
          'email': data['email'],
          'email_verified_at': '2026-11-14T10:00:00Z',
        };
        return {'message': 'Email updated.', 'data': user};
    }
    fail('unexpected POST $endpoint');
  }
}

ApiError _field(String key, String message) => ApiError(
  message: message,
  statusCode: 422,
  fieldErrors: {
    key: [message],
  },
);

void main() {
  final preferences = PreferencesManager();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.saveToken('email-change-test');
  });
  tearDown(() => preferences.clear());

  group('maskEmail / isValidEmail', () {
    test('keeps 3 leading and 2 trailing local characters', () {
      expect(maskEmail(_current), 'Sal******21@gmail.com');
      expect(maskEmail('ab@x.io'), 'a******@x.io');
      expect(maskEmail('abcd@x.io'), 'a******@x.io');
      expect(maskEmail('not-an-email'), 'not-an-email');
    });

    test('validates format and API max length', () {
      expect(isValidEmail('new@mail.com'), true);
      expect(isValidEmail('new@mail'), false);
      expect(isValidEmail('new mail@x.com'), false);
      expect(isValidEmail('${'a' * 250}@x.com'), false);
    });
  });

  Future<(CurrentUserCubit, _EmailApi)> show(
    WidgetTester tester, {
    bool verified = true,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _EmailApi(verified: verified);
    final user = CurrentUserCubit(
      profileRepo: ProfileRepo(apiService: api),
      settingsRepo: SettingsRepo(
        apiService: api,
        supportedCurrencies: {'AED', 'USD'},
      ),
    );
    addTearDown(user.close);
    await user.load();
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => EmailAddressScreen(
                      currentUser: user,
                      authRepo: AuthRepo(apiService: api),
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await _settle(tester);
    return (user, api);
  }

  final emailField = find.descendant(
    of: find.byKey(const ValueKey('new-email')),
    matching: find.byType(TextField),
  );
  final passwordField = find.descendant(
    of: find.byKey(const ValueKey('email-change-password')),
    matching: find.byType(TextField),
  );
  ElevatedButton verifyButton(WidgetTester tester) =>
      tester.widget<ElevatedButton>(
        find.descendant(
          of: find.byKey(const ValueKey('verify-new-email')),
          matching: find.byType(ElevatedButton),
        ),
      );

  testWidgets('shows the masked current email and the Verified chip', (
    tester,
  ) async {
    await show(tester);
    expect(find.text('Sal******21@gmail.com'), findsOneWidget);
    expect(find.byKey(const ValueKey('email-verified')), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(
      find.text("We'll send an OTP to your new email address"),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(emailField).cursorColor, Colors.white);
    expect(tester.getSize(find.byTooltip('Back')), const Size(44, 44));
  });

  testWidgets('unverified accounts show "Not verified"', (tester) async {
    await show(tester, verified: false);
    expect(find.byKey(const ValueKey('email-not-verified')), findsOneWidget);
    expect(find.text('Not verified'), findsOneWidget);
  });

  testWidgets('Verify stays disabled until a valid, different email', (
    tester,
  ) async {
    await show(tester);
    expect(verifyButton(tester).onPressed, isNull);
    await tester.enterText(emailField, 'new@mail');
    await tester.pump();
    expect(verifyButton(tester).onPressed, isNull);
    await tester.enterText(emailField, _current.toUpperCase());
    await tester.pump();
    expect(verifyButton(tester).onPressed, isNull);
    expect(find.text('This is already your email address'), findsOneWidget);
    await tester.enterText(emailField, 'new@mail.com');
    await tester.pump();
    expect(verifyButton(tester).onPressed, isNotNull);
  });

  testWidgets('back with a typed email asks before discarding', (tester) async {
    await show(tester);
    // Clean: back leaves at once.
    await tester.tap(find.byTooltip('Back'));
    await _settle(tester);
    expect(find.byType(EmailAddressScreen), findsNothing);

    await tester.tap(find.text('Open'));
    await _settle(tester);
    await tester.enterText(emailField, 'new@mail.com');
    await tester.pump();
    // Android back.
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.text('Discard Changes?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await _settle(tester);
    expect(find.byType(EmailAddressScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await _settle(tester);
    await tester.tap(find.text('Discard'));
    await _settle(tester);
    expect(find.byType(EmailAddressScreen), findsNothing);
  });

  testWidgets(
    'password dialog → wrong password error → OTP → email updated + toast',
    (tester) async {
      final (user, api) = await show(tester);
      api.changeResults.add(
        _field('current_password', 'The password is incorrect.'),
      );
      await tester.enterText(emailField, 'new@mail.com');
      await tester.pump();
      await tester.tap(find.text('Verify New Email'));
      await _settle(tester);
      expect(find.byType(GlassConfirmDialog), findsOneWidget);

      // Send is disabled until a password is typed.
      await tester.tap(find.text('Send code'));
      await tester.pump();
      expect(api.posts, isEmpty);

      await tester.enterText(passwordField, 'wrong-pass');
      await tester.pump();
      await tester.tap(find.text('Send code'));
      await _settle(tester);
      expect(
        tester.widget<TextField>(passwordField).decoration!.errorText,
        'The password is incorrect.',
      );
      expect(find.byType(OtpVerificationScreen), findsNothing);

      await tester.enterText(passwordField, 'right-pass');
      await tester.pump();
      await tester.tap(find.text('Send code'));
      await _settle(tester);
      expect(api.posts.last.$1, 'email/change');
      expect(api.posts.last.$2, {
        'current_password': 'right-pass',
        'email': 'new@mail.com',
      });
      expect(find.byType(GlassConfirmDialog), findsNothing);
      expect(find.text('Verify your new email'), findsOneWidget);

      // Resend re-posts the change request (no resend endpoint for it).
      await tester.pump(const Duration(seconds: 61));
      await tester.tap(find.text('Resend OTP'));
      await _settle(tester);
      expect(api.posts.where((p) => p.$1 == 'email/change'), hasLength(3));

      await tester.enterText(find.byType(EditableText).first, '1234');
      await _settle(tester);
      expect(api.posts.last.$1, 'email/change/verify');
      expect(api.posts.last.$2, {'email': 'new@mail.com', 'code': '1234'});
      expect(find.byType(OtpVerificationScreen), findsNothing);
      expect(find.byType(EmailAddressScreen), findsNothing);
      expect(user.state.profile?.email, 'new@mail.com');
      expect(find.text('Your email address was updated'), findsOneWidget);
    },
  );

  testWidgets('a taken email closes the dialog and shows under the field', (
    tester,
  ) async {
    final (_, api) = await show(tester);
    api.changeResults.add(_field('email', 'This email is already taken.'));
    await tester.enterText(emailField, 'taken@mail.com');
    await tester.pump();
    await tester.tap(find.text('Verify New Email'));
    await _settle(tester);
    await tester.enterText(passwordField, 'right-pass');
    await tester.pump();
    await tester.tap(find.text('Send code'));
    await _settle(tester);
    expect(find.byType(GlassConfirmDialog), findsNothing);
    expect(find.byType(OtpVerificationScreen), findsNothing);
    expect(
      tester.widget<TextField>(emailField).decoration!.errorText,
      'This email is already taken.',
    );
  });

  testWidgets('a wrong OTP keeps the OTP screen and the old email', (
    tester,
  ) async {
    final (user, api) = await show(tester);
    api.verifyError = ApiError(message: 'Invalid code.', statusCode: 422);
    await tester.enterText(emailField, 'new@mail.com');
    await tester.pump();
    await tester.tap(find.text('Verify New Email'));
    await _settle(tester);
    await tester.enterText(passwordField, 'right-pass');
    await tester.pump();
    await tester.tap(find.text('Send code'));
    await _settle(tester);
    await tester.enterText(find.byType(EditableText).first, '0000');
    await _settle(tester);
    expect(find.byType(OtpVerificationScreen), findsOneWidget);
    expect(find.text('Invalid code.'), findsOneWidget);
    expect(user.state.profile?.email, _current);
    // Let the resend countdown finish so no timer is left pending.
    await tester.pump(const Duration(seconds: 61));
  });

  testWidgets('the Settings Email row shows the masked email and opens it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _EmailApi();
    final user = CurrentUserCubit(
      profileRepo: ProfileRepo(apiService: api),
      settingsRepo: SettingsRepo(
        apiService: api,
        supportedCurrencies: {'AED', 'USD'},
      ),
    );
    addTearDown(user.close);
    await user.load();
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: SettingsScreen(
            currentUser: user,
            authRepo: AuthRepo(apiService: api),
          ),
        ),
      ),
    );
    await _settle(tester);
    final row = find.byKey(const ValueKey('settings-email'));
    expect(
      find.descendant(of: row, matching: find.text('Sal******21@gmail.com')),
      findsOneWidget,
    );
    await tester.tap(row);
    await _settle(tester);
    expect(find.byType(EmailAddressScreen), findsOneWidget);
  });
}
