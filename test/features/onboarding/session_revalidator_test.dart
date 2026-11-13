import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/onboarding/cubit/session_revalidator.dart';
import 'onboarding_fixtures.dart';

void main() {
  final preferences = PreferencesManager();
  late StartupAuth auth;
  late int signedOut;
  const backoff = [Duration(milliseconds: 20), Duration(milliseconds: 40)];
  Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.saveToken('candidate');
    auth = StartupAuth();
    signedOut = 0;
  });
  tearDown(() => preferences.clear());
  ApiError offline() =>
      ApiError(message: 'Connection failed', isConnectionError: true);

  test('401 after an offline start clears the session and signs out', () async {
    auth.handler = () async => throw offline();
    final revalidator = SessionRevalidator(auth: auth, backoff: backoff)
      ..start(onSignedOut: () => signedOut++);
    await pumpEventQueue();
    expect(auth.calls, 1);
    auth.handler = () async =>
        throw ApiError(message: 'Unauthenticated', statusCode: 401);
    await wait(30);
    await pumpEventQueue();
    expect(auth.calls, 2);
    expect(signedOut, 1);
    expect(preferences.hasSession, false);
    expect(revalidator.isDone, true);
  });

  test('network failures back off, then success stops quietly', () async {
    auth.handler = () async => throw offline();
    final revalidator = SessionRevalidator(auth: auth, backoff: backoff)
      ..start(onSignedOut: () => signedOut++);
    await wait(30);
    expect(auth.calls, 2);
    auth.handler = () async => startupUser();
    await wait(60);
    expect(auth.calls, 3);
    expect(revalidator.isDone, true);
    await wait(100);
    expect(auth.calls, 3);
    expect(signedOut, 0);
    expect(preferences.hasSession, true);
  });

  test('retryNow skips the backoff (app resumed)', () async {
    auth.handler = () async => throw offline();
    final revalidator = SessionRevalidator(
      auth: auth,
      backoff: const [Duration(minutes: 1)],
    )..start(onSignedOut: () => signedOut++);
    await pumpEventQueue();
    auth.handler = () async => startupUser();
    revalidator.retryNow();
    await pumpEventQueue();
    expect(auth.calls, 2);
    expect(revalidator.isDone, true);
  });

  test('a session change stops retries without signing out', () async {
    auth.handler = () async => throw offline();
    final revalidator = SessionRevalidator(auth: auth, backoff: backoff)
      ..start(onSignedOut: () => signedOut++);
    await pumpEventQueue();
    await preferences.saveToken('other');
    auth.handler = () async =>
        throw ApiError(message: 'Unauthenticated', statusCode: 401);
    await wait(100);
    expect(auth.calls, 1);
    expect(signedOut, 0);
    expect(revalidator.isDone, true);
    expect(preferences.hasSession, true);
  });
}
