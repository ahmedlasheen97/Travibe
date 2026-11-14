import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/travibe_toast.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';
import 'package:travibe/features/profile/screens/change_password_screen.dart';

class _PasswordApi extends ApiService {
  final patches = <(String, Map<String, dynamic>)>[];

  /// Thrown by the next `PATCH password`; null succeeds.
  Object? error;

  /// When set, `PATCH password` waits for it (to test double taps).
  Completer<void>? gate;

  @override
  Future<dynamic> patch(String endpoint, Map<String, dynamic> data) async {
    patches.add((endpoint, Map.of(data)));
    await gate?.future;
    if (error case final e?) throw e;
    return {'message': 'Password updated.'};
  }
}

final _toasts = TravibeToastController();

Future<void> _open(WidgetTester tester, _PasswordApi api) async {
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, _) => TravibeToastScope(
        controller: _toasts,
        child: MaterialApp(
          theme: darkTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ChangePasswordScreen(repo: AuthRepo(apiService: api)),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Finder _field(int i) => find.byType(TextFormField).at(i);

Future<void> _fill(
  WidgetTester tester, {
  String current = 'OldPass123!',
  String password = 'NewPass456!',
  String? confirm,
}) async {
  await tester.enterText(_field(0), current);
  await tester.enterText(_field(1), password);
  await tester.enterText(_field(2), confirm ?? password);
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.text('Update Password'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    _toasts.dismiss();
  });

  testWidgets('client validation blocks the request', (tester) async {
    final api = _PasswordApi();
    await _open(tester, api);

    await _submit(tester);
    expect(find.text('Please enter your current password'), findsOneWidget);
    expect(find.text('Please enter a new password'), findsOneWidget);

    await _fill(tester, password: 'short');
    await _submit(tester);
    expect(find.text('Password must be at least 8 characters'), findsOneWidget);

    await _fill(tester, confirm: 'Different789!');
    await _submit(tester);
    expect(find.text('Passwords do not match'), findsOneWidget);

    expect(api.patches, isEmpty);
    expect(find.byType(ChangePasswordScreen), findsOneWidget);
    _toasts.dismiss();
  });

  testWidgets('success sends PATCH password, toasts and pops', (tester) async {
    final api = _PasswordApi();
    await _open(tester, api);
    await _fill(tester);
    await _submit(tester);

    expect(api.patches, hasLength(1));
    expect(api.patches.single.$1, 'password');
    expect(api.patches.single.$2, {
      'current_password': 'OldPass123!',
      'password': 'NewPass456!',
      'password_confirmation': 'NewPass456!',
    });
    expect(find.byType(ChangePasswordScreen), findsNothing);
    expect(_toasts.current?.data.message, 'Password updated');
    expect(_toasts.current?.data.variant, TravibeToastVariant.success);
    _toasts.dismiss();
  });

  testWidgets('wrong current password shows under that field', (tester) async {
    const message = 'The current password is incorrect.';
    final api = _PasswordApi()
      ..error = ApiError(
        message: message,
        statusCode: 422,
        fieldErrors: {
          'current_password': [message],
        },
      );
    await _open(tester, api);
    await _fill(tester);
    await _submit(tester);

    expect(find.byType(ChangePasswordScreen), findsOneWidget);
    expect(find.text(message), findsOneWidget);
    expect(_toasts.current, isNull);

    await tester.enterText(_field(0), 'OldPass1234!');
    await tester.pump();
    expect(find.text(message), findsNothing);
    _toasts.dismiss();
  });

  testWidgets('other failures show an error toast and stay', (tester) async {
    final api = _PasswordApi()
      ..error = ApiError(message: 'No internet connection', statusCode: null);
    await _open(tester, api);
    await _fill(tester);
    await _submit(tester);

    expect(find.byType(ChangePasswordScreen), findsOneWidget);
    expect(_toasts.current?.data.message, 'No internet connection');
    expect(_toasts.current?.data.variant, TravibeToastVariant.error);
    _toasts.dismiss();
  });

  testWidgets('a double tap sends one request', (tester) async {
    final api = _PasswordApi()..gate = Completer<void>();
    await _open(tester, api);
    await _fill(tester);
    await tester.tap(find.text('Update Password'));
    await tester.pump();
    await tester.tap(find.byType(ElevatedButton), warnIfMissed: false);
    await tester.pump();
    expect(api.patches, hasLength(1));

    api.gate!.complete();
    await tester.pumpAndSettle();
    expect(api.patches, hasLength(1));
    expect(find.byType(ChangePasswordScreen), findsNothing);
    _toasts.dismiss();
  });
}
