import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/travibe_toast.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';
import 'package:travibe/features/auth/screens/otp_verification_screen.dart';

/// The pin cursor blinks forever, so pumpAndSettle never settles here.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _OtpApi extends ApiService {
  final posts = <(String, Map<String, dynamic>)>[];
  Object? verifyError;

  @override
  Future<dynamic> post(String endpoint, Map<String, dynamic> data) async {
    posts.add((endpoint, Map.of(data)));
    if (endpoint == 'email/verify-code' && verifyError != null) {
      throw verifyError!;
    }
    return {'message': 'ok'};
  }
}

Future<void> _pump(WidgetTester tester, Widget otp) async {
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
                MaterialPageRoute<Object?>(builder: (_) => otp),
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
}

Finder _toast(String text) => find.descendant(
  of: find.byType(TravibeToastView),
  matching: find.text(text),
);

String _pin(WidgetTester tester) => tester
    .widget<EditableText>(find.byType(EditableText).first)
    .controller
    .text;

Future<void> _enterCode(WidgetTester tester, String code) async {
  await tester.enterText(find.byType(EditableText).first, code);
  await _settle(tester);
}

void main() {
  testWidgets('default (signup) path verifies and resends via AuthRepo', (
    tester,
  ) async {
    final api = _OtpApi()
      ..verifyError = ApiError(message: 'Invalid code', statusCode: 422);
    await _pump(
      tester,
      OtpVerificationScreen(
        email: 'user@mail.com',
        authRepo: AuthRepo(apiService: api),
      ),
    );

    expect(find.text('Verify your email'), findsOneWidget);

    await _enterCode(tester, '1234');
    expect(api.posts.last.$1, 'email/verify-code');
    expect(api.posts.last.$2['email'], 'user@mail.com');
    expect(api.posts.last.$2['code'], '1234');
    // A wrong code keeps the screen, shows the red toast and clears the
    // boxes with focus back on the field.
    expect(find.byType(OtpVerificationScreen), findsOneWidget);
    expect(_toast(otpWrongMessage), findsOneWidget);
    expect(
      tester
          .widget<TravibeToastView>(find.byType(TravibeToastView))
          .data
          .variant,
      TravibeToastVariant.error,
    );
    expect(find.textContaining('ApiError'), findsNothing);
    expect(find.textContaining('Verification failed'), findsNothing);
    expect(_pin(tester), isEmpty);
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).first)
          .focusNode
          .hasFocus,
      isTrue,
    );

    await tester.pump(const Duration(seconds: 61));
    await tester.tap(find.text('Resend OTP'));
    await _settle(tester);
    expect(api.posts.last.$1, 'email/resend-code');
    expect(api.posts.last.$2, {'email': 'user@mail.com'});
    expect(api.posts.map((p) => p.$1), isNot(contains('forgot-password')));
    expect(_toast('A new code has been sent to your email'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  for (final message in [
    'Invalid or expired code.',
    'The code is invalid.',
    'The code has expired.',
  ]) {
    testWidgets('a 422 "$message" shows Wrong OTP Try Again', (tester) async {
      final api = _OtpApi()
        ..verifyError = ApiError(message: message, statusCode: 422);
      await _pump(
        tester,
        OtpVerificationScreen(
          email: 'user@mail.com',
          authRepo: AuthRepo(apiService: api),
        ),
      );
      await _enterCode(tester, '1234');
      expect(_toast(otpWrongMessage), findsOneWidget);
      expect(find.textContaining('expired'), findsNothing);
      expect(_pin(tester), isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
  }

  test('otpFailureMessage maps errors to user-facing text', () {
    expect(
      otpFailureMessage(
        ApiError(message: 'Invalid or expired code.', statusCode: 422),
      ),
      otpWrongMessage,
    );
    expect(
      otpFailureMessage(
        ApiError(message: 'No internet connection.', isConnectionError: true),
      ),
      'No internet connection.',
    );
    expect(otpFailureMessage(StateError('boom')), ApiError.fallbackMessage);
  });

  testWidgets('the OTP cursor is white', (tester) async {
    await _pump(
      tester,
      OtpVerificationScreen(
        email: 'user@mail.com',
        authRepo: AuthRepo(apiService: _OtpApi()),
      ),
    );
    final field = tester.widget<MaterialPinField>(
      find.byType(MaterialPinField),
    );
    expect(field.theme!.cursorColor, Colors.white);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the 5th wrong code locks Verify until Resend OTP', (
    tester,
  ) async {
    final api = _OtpApi()
      ..verifyError = ApiError(
        message: 'Invalid or expired code.',
        statusCode: 422,
      );
    await _pump(
      tester,
      OtpVerificationScreen(
        email: 'user@mail.com',
        authRepo: AuthRepo(apiService: api),
      ),
    );
    int verifies() =>
        api.posts.where((p) => p.$1 == 'email/verify-code').length;
    VoidCallback? verifyButton() => tester
        .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Verify'))
        .onPressed;

    for (var i = 1; i < otpMaxAttempts; i++) {
      await _enterCode(tester, '1234');
      expect(_toast(otpWrongMessage), findsOneWidget, reason: 'attempt $i');
      expect(verifyButton(), isNotNull);
    }
    await _enterCode(tester, '1234');
    expect(verifies(), otpMaxAttempts);
    expect(_toast(otpTooManyMessage), findsOneWidget);
    expect(_pin(tester), isEmpty);
    expect(verifyButton(), isNull);

    // A 6th code is not sent while locked.
    await _enterCode(tester, '5678');
    expect(verifies(), otpMaxAttempts);
    expect(_toast(otpTooManyMessage), findsOneWidget);

    // Resend starts a fresh code: counter reset, Verify enabled again.
    await tester.pump(const Duration(seconds: 61));
    await tester.tap(find.text('Resend OTP'));
    await _settle(tester);
    expect(api.posts.last.$1, 'email/resend-code');
    expect(verifyButton(), isNotNull);
    await _enterCode(tester, '1234');
    expect(verifies(), otpMaxAttempts + 1);
    expect(_toast(otpWrongMessage), findsOneWidget);
    expect(verifyButton(), isNotNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('OtpAttempts counts only wrong codes and resets on resend', () {
    final wrong = ApiError(
      message: 'Invalid or expired code.',
      statusCode: 422,
    );
    final attempts = OtpAttempts();

    // Network errors are not wrong attempts.
    expect(
      attempts.fail(ApiError(message: 'Offline', isConnectionError: true)),
      'Offline',
    );
    expect(attempts.wrong, 0);

    for (var i = 1; i < otpMaxAttempts; i++) {
      expect(attempts.fail(wrong), otpWrongMessage);
    }
    expect(attempts.locked, isFalse);
    expect(attempts.fail(wrong), otpTooManyMessage);
    expect(attempts.locked, isTrue);

    attempts.reset();
    expect(attempts.wrong, 0);
    expect(attempts.locked, isFalse);
    expect(attempts.fail(wrong), otpWrongMessage);
  });

  testWidgets('custom callbacks replace the signup flow', (tester) async {
    final api = _OtpApi();
    final codes = <String>[];
    var resends = 0;
    var verified = 0;
    await _pump(
      tester,
      OtpVerificationScreen(
        email: 'new@mail.com',
        title: 'Verify your new email',
        authRepo: AuthRepo(apiService: api),
        onVerify: (code) async {
          codes.add(code);
          if (code == '0000') throw ApiError(message: 'Wrong code');
        },
        onResend: () async => resends++,
        onVerified: (context) {
          verified++;
          Navigator.pop(context, 'done');
        },
      ),
    );

    expect(find.text('Verify your new email'), findsOneWidget);

    await tester.pump(const Duration(seconds: 61));
    await tester.tap(find.text('Resend OTP'));
    await _settle(tester);
    expect(resends, 1);

    await _enterCode(tester, '0000');
    expect(codes, ['0000']);
    expect(verified, 0);
    expect(_toast('Wrong code'), findsOneWidget);
    expect(find.byType(OtpVerificationScreen), findsOneWidget);

    // Like a user, delete the wrong code before typing a new one.
    await _enterCode(tester, '');
    await _enterCode(tester, '1234');
    expect(codes, ['0000', '1234']);
    expect(verified, 1);
    expect(find.byType(OtpVerificationScreen), findsNothing);
    // The custom flow never touches the signup endpoints.
    expect(api.posts, isEmpty);

    await tester.pumpWidget(const SizedBox());
  });
}
