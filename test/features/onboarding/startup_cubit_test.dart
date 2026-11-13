import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';
import 'package:travibe/features/onboarding/cubit/startup_cubit.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'onboarding_fixtures.dart';

class UserApi extends ApiService {
  String? endpoint;
  dynamic response;
  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
    this.endpoint = endpoint;
    return response;
  }
}

void main() {
  final preferences = PreferencesManager();
  late StartupAuth auth;
  late StartupCubit startup;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    auth = StartupAuth();
    startup = StartupCubit(
      auth: auth,
      retryDelays: const [Duration.zero, Duration.zero],
    );
  });
  tearDown(() async {
    await startup.close();
    await preferences.clear();
  });

  test('first launch goes to onboarding even with a stored token', () async {
    await preferences.saveToken('candidate');
    await startup.resolve();
    expect(startup.state.decision!.target, StartupTarget.onboarding);
    expect(auth.calls, 0);
    expect(preferences.onboardingCompleted, false);
  });
  test(
    'returning unauthenticated launch goes to login without a user request',
    () async {
      await preferences.completeOnboarding();
      await startup.resolve();
      expect(startup.state.decision!.target, StartupTarget.login);
      expect(auth.calls, 0);
    },
  );
  test(
    'returning verified complete account is validated before home',
    () async {
      await preferences.completeOnboarding();
      await preferences.saveToken('candidate');
      final gate = Completer<ProfileModel>();
      auth.handler = () => gate.future;
      final pending = startup.resolve();
      expect(startup.state.decision, isNull);
      gate.complete(startupUser());
      await pending;
      expect(auth.calls, greaterThan(0));
      expect(startup.state.decision!.target, StartupTarget.home);
    },
  );
  test(
    'invalid/revoked token goes to login and preserves app preferences',
    () async {
      await preferences.completeOnboarding();
      await preferences.saveLanguage('ar');
      auth.handler = () async =>
          throw ApiError(message: 'Unauthenticated', statusCode: 401);
      await preferences.saveToken('invalid');
      await startup.resolve();
      expect(startup.state.decision!.target, StartupTarget.login);
      expect(preferences.hasSession, false);
      expect(preferences.onboardingCompleted, true);
      expect(preferences.getLanguage(), 'ar');
    },
  );
  test('logout then relaunch goes to login with completion intact', () async {
    await preferences.completeOnboarding();
    await preferences.saveToken('valid');
    await preferences.clearSession();
    await preferences.init();
    await startup.resolve();
    expect(startup.state.decision!.target, StartupTarget.login);
  });
  test(
    'network/server failures retain credentials, retry can validate',
    () async {
      await preferences.completeOnboarding();
      auth.handler = () async =>
          throw ApiError(message: 'Unavailable', statusCode: 503);
      await preferences.saveToken('candidate');
      await pumpEventQueue();
      auth.calls = 0;
      await startup.resolve();
      expect(startup.state.decision, isNull);
      expect(startup.state.error, isNotNull);
      expect(auth.calls, 3, reason: '5xx is retried before showing an error');
      expect(await preferences.getToken(), 'candidate');
      auth.handler = () async => startupUser(locale: 'ar');
      await startup.resolve();
      expect(startup.state.decision!.target, StartupTarget.home);
      expect(preferences.language.value, 'ar');
    },
  );
  test(
    'forbidden session returns to login without claiming revocation',
    () async {
      await preferences.completeOnboarding();
      auth.handler = () async =>
          throw ApiError(message: 'Forbidden', statusCode: 403);
      await preferences.saveToken('restricted');
      await startup.resolve();
      expect(startup.state.decision!.target, StartupTarget.login);
      expect(preferences.hasSession, true);
    },
  );
  test('unverified account resumes existing email verification', () async {
    await preferences.completeOnboarding();
    auth.handler = () async => startupUser(verified: false);
    await preferences.saveToken('candidate');
    await startup.resolve();
    expect(startup.state.decision!.target, StartupTarget.verification);
    expect(startup.state.decision!.email, 'traveler@example.invalid');
  });
  test(
    'verified incomplete account resumes profile setup rather than home',
    () async {
      await preferences.completeOnboarding();
      auth.handler = () async => startupUser(complete: false);
      await preferences.saveToken('candidate');
      await startup.resolve();
      expect(startup.state.decision!.target, StartupTarget.profileSetup);
    },
  );
  for (final oldFailure in [false, true]) {
    test(
      'late ${oldFailure ? '401' : 'account locale'} cannot affect a replacement session',
      () async {
        await preferences.completeOnboarding();
        final gate = Completer<ProfileModel>();
        auth.handler = () => gate.future;
        await preferences.saveToken('old');
        final pending = startup.resolve();
        auth.handler = () async => startupUser(locale: 'en');
        await preferences.saveToken('new');
        await startup.resolve();
        if (oldFailure) {
          gate.completeError(
            ApiError(message: 'Unauthenticated', statusCode: 401),
          );
        } else {
          gate.complete(startupUser(locale: 'ar'));
        }
        await pending;
        expect(await preferences.getToken(), 'new');
        expect(preferences.language.value, 'en');
        expect(startup.state.decision!.target, StartupTarget.home);
      },
    );
  }
  group('resilient session check', () {
    setUp(() async {
      await preferences.completeOnboarding();
      await preferences.saveToken('candidate');
      // saveToken notifies the cubit's session listener; start each case clean.
      await pumpEventQueue();
      await preferences.remove(StartupCubit.confirmedHomeKey);
      auth.calls = 0;
    });
    ApiError offline() =>
        ApiError(message: 'Connection failed', isConnectionError: true);

    test('first check with unknown outcome (timeout) is retried', () async {
      var first = true;
      auth.handler = () async {
        if (first) {
          first = false;
          throw TimeoutException('first request');
        }
        return startupUser();
      };
      final errors = <String?>[];
      final sub = startup.stream.listen((s) => errors.add(s.error));
      await startup.resolve();
      await sub.cancel();
      expect(auth.calls, 2);
      expect(errors.whereType<String>(), isEmpty);
      expect(startup.state.decision!.target, StartupTarget.home);
      expect(startup.state.decision!.offline, false);
    });

    test('transient connection failure then success goes home', () async {
      var failures = 2;
      auth.handler = () async {
        if (failures-- > 0) throw offline();
        return startupUser();
      };
      await startup.resolve();
      expect(auth.calls, 3);
      expect(startup.state.decision!.target, StartupTarget.home);
      expect(preferences.getBool(StartupCubit.confirmedHomeKey), true);
    });

    test('offline with a confirmed saved session continues to home', () async {
      await preferences.setBool(StartupCubit.confirmedHomeKey, true);
      auth.handler = () async => throw offline();
      await startup.resolve();
      expect(auth.calls, 3);
      expect(startup.state.error, isNull);
      expect(startup.state.decision!.target, StartupTarget.home);
      expect(startup.state.decision!.offline, true);
      expect(await preferences.getToken(), 'candidate');
    });

    test('offline without a confirmed home shows retry instead', () async {
      auth.handler = () async => throw TimeoutException('offline');
      await startup.resolve();
      expect(startup.state.decision, isNull);
      expect(startup.state.error, StartupCubit.errorMessage);
      expect(preferences.hasSession, true);
    });

    test('401 is not retried and sends to login', () async {
      await preferences.setBool(StartupCubit.confirmedHomeKey, true);
      auth.handler = () async =>
          throw ApiError(message: 'Unauthenticated', statusCode: 401);
      await startup.resolve();
      expect(auth.calls, 1);
      expect(startup.state.decision!.target, StartupTarget.login);
      expect(preferences.hasSession, false);
      expect(preferences.getBool(StartupCubit.confirmedHomeKey), isNull);
    });

    test('incomplete profile clears the confirmed-home flag', () async {
      await preferences.setBool(StartupCubit.confirmedHomeKey, true);
      auth.handler = () async => startupUser(complete: false);
      await startup.resolve();
      expect(startup.state.decision!.target, StartupTarget.profileSetup);
      expect(preferences.getBool(StartupCubit.confirmedHomeKey), isNull);
    });

    test(
      'retrying from an error keeps the error visible while loading',
      () async {
        auth.handler = () async =>
            throw ApiError(message: 'x', statusCode: 500);
        await startup.resolve();
        final gate = Completer<ProfileModel>();
        auth.handler = () => gate.future;
        final pending = startup.resolve();
        expect(startup.state.loading, true);
        expect(startup.state.error, isNotNull);
        gate.complete(startupUser());
        await pending;
        expect(startup.state.decision!.target, StartupTarget.home);
      },
    );
  });
  test(
    'AuthRepo validates documented /user identity and required routing fields',
    () async {
      final api = UserApi()
        ..response = {
          'data': {
            'id': 7,
            'email': 'traveler@example.invalid',
            'locale': 'ar',
            'email_verified_at': '2026-10-01',
            'profile_completed': true,
          },
        };
      final user = await AuthRepo(apiService: api).currentUser();
      expect(api.endpoint, 'user');
      expect(user.profileCompleted, true);
      expect(user.locale, 'ar');
      api.response = {
        'data': {'id': 7},
      };
      await expectLater(
        AuthRepo(apiService: api).currentUser(),
        throwsA(isA<ApiError>()),
      );
    },
  );
}
