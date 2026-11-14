import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/core/theme/dark_theme.dart';
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
    // A wrong code keeps the screen and uses the original snackbar.
    expect(find.byType(OtpVerificationScreen), findsOneWidget);
    expect(find.textContaining('Verification failed'), findsOneWidget);

    await tester.pump(const Duration(seconds: 61));
    await tester.tap(find.text('Resend OTP'));
    await _settle(tester);
    expect(api.posts.last.$1, 'email/resend-code');
    expect(api.posts.last.$2, {'email': 'user@mail.com'});
    expect(api.posts.map((p) => p.$1), isNot(contains('forgot-password')));

    await tester.pumpWidget(const SizedBox());
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
    expect(find.text('Wrong code'), findsOneWidget);
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
