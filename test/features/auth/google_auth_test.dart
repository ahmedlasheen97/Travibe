import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
// Platform fake exercises the installed plugin API without native UI.
// ignore: depend_on_referenced_packages
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart'
    as platform;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/auth/cubit/auth_cubit.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';
import 'package:travibe/features/auth/data/google_auth_service.dart';

Map<String, dynamic> authJson({bool verify = false}) => {
  'data': {
    'token': 'travibe-test-token',
    'token_type': 'Bearer',
    'expires_at': '2026-12-01T00:00:00Z',
    'email_verification_required': verify,
    'user': {'id': 7, 'name': 'Traveler', 'email': 'test@example.invalid'},
  },
};

class FakeApi extends ApiService {
  final calls = <String>[];
  Map<String, dynamic>? body;
  Future<dynamic> Function() handler = () async => authJson();
  @override
  Future<dynamic> post(String endpoint, Map<String, dynamic> data) {
    calls.add(endpoint);
    body = data;
    return handler();
  }
}

class FakeGoogle extends GoogleAuthService {
  int calls = 0;
  Future<String?> Function() handler = () async => 'google-test-id-token';
  @override
  Future<String?> signIn() {
    calls++;
    return handler();
  }
}

class NativeGoogle extends platform.GoogleSignInPlatform {
  int initializations = 0;
  platform.InitParameters? parameters;
  String? token = 'native-test-token';
  Object? failure;
  @override
  Future<void> init(platform.InitParameters params) async {
    initializations++;
    parameters = params;
  }

  @override
  Future<platform.AuthenticationResults> authenticate(
    platform.AuthenticateParameters params,
  ) async {
    if (failure != null) throw failure!;
    return platform.AuthenticationResults(
      user: const platform.GoogleSignInUserData(
        email: 'test@example.invalid',
        id: '7',
      ),
      authenticationTokens: platform.AuthenticationTokenData(idToken: token),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final session = PreferencesManager();
  final native = NativeGoogle();
  final previousPlatform = platform.GoogleSignInPlatform.instance;
  setUpAll(() => platform.GoogleSignInPlatform.instance = native);
  tearDownAll(() => platform.GoogleSignInPlatform.instance = previousPlatform);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await session.init();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    native.token = 'native-test-token';
    native.failure = null;
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await session.clear();
  });

  test('native initialization uses both client IDs exactly once', () async {
    expect(await GoogleAuthService().signIn(), 'native-test-token');
    expect(await GoogleAuthService().signIn(), 'native-test-token');
    expect(native.initializations, 1);
    expect(native.parameters!.clientId, GoogleAuthService.iosClientId);
    expect(native.parameters!.serverClientId, GoogleAuthService.webClientId);
  });
  test('native missing ID token is rejected', () async {
    native.token = null;
    await expectLater(GoogleAuthService().signIn(), throwsA(isA<ApiError>()));
  });
  test('native cancellation is returned without an error', () async {
    native.failure = const GoogleSignInException(
      code: GoogleSignInExceptionCode.canceled,
    );
    expect(await GoogleAuthService().signIn(), isNull);
  });
  test(
    'native errors produce safe feedback without exception details',
    () async {
      native.failure = const GoogleSignInException(
        code: GoogleSignInExceptionCode.unknownError,
        description: 'sensitive-test-description',
      );
      await expectLater(
        GoogleAuthService().signIn(),
        throwsA(
          isA<ApiError>().having(
            (e) => e.message,
            'safe message',
            isNot(contains('sensitive')),
          ),
        ),
      );
    },
  );
  test(
    'Google login serializes exchange, persists Travibe token and emits success',
    () async {
      final api = FakeApi();
      final cubit = AuthCubit(
        repo: AuthRepo(apiService: api),
        google: FakeGoogle(),
      );
      final states = <AuthState>[];
      final subscription = cubit.stream.listen(states.add);
      await cubit.loginWithGoogle();
      expect(api.calls, ['auth/google/token']);
      expect(api.body, {
        'device_name': 'iPhone',
        'id_token': 'google-test-id-token',
        'nonce': null,
        'name': null,
      });
      expect(await session.getToken(), 'travibe-test-token');
      expect(session.hasSession, true);
      expect((cubit.state as AuthSuccess).response!.user.id, '7');
      await Future<void>.delayed(Duration.zero);
      expect(states.first, isA<AuthLoading>());
      expect(states.last, isA<AuthSuccess>());
      await subscription.cancel();
      await cubit.close();
    },
  );
  test(
    'verification requirement and email remain available for OTP navigation',
    () async {
      final api = FakeApi()..handler = () async => authJson(verify: true);
      final cubit = AuthCubit(
        repo: AuthRepo(apiService: api),
        google: FakeGoogle(),
      );
      await cubit.loginWithGoogle();
      final response = (cubit.state as AuthSuccess).response!;
      expect(response.emailVerificationRequired, true);
      expect(response.user.email, 'test@example.invalid');
      await cubit.close();
    },
  );
  test('cancelled sign-in does not call backend or save a session', () async {
    final google = FakeGoogle()..handler = () async => null;
    final api = FakeApi();
    final cubit = AuthCubit(
      repo: AuthRepo(apiService: api),
      google: google,
    );
    await cubit.loginWithGoogle();
    expect(cubit.state, isA<AuthInitial>());
    expect(api.calls, isEmpty);
    expect(session.hasSession, false);
    await cubit.close();
  });
  test('empty ID token does not reach the backend', () async {
    final api = FakeApi();
    final cubit = AuthCubit(
      repo: AuthRepo(apiService: api),
      google: FakeGoogle()..handler = () async => '',
    );
    await cubit.loginWithGoogle();
    expect(cubit.state, isA<AuthFailure>());
    expect(api.calls, isEmpty);
    await cubit.close();
  });
  for (final status in [401, 403, 422, null]) {
    test('backend error $status preserves session and allows retry', () async {
      await session.saveToken('existing-test-session');
      final api = FakeApi()
        ..handler = () async =>
            throw ApiError(message: 'Sign-in failed', statusCode: status);
      final cubit = AuthCubit(
        repo: AuthRepo(apiService: api),
        google: FakeGoogle(),
      );
      await cubit.loginWithGoogle();
      expect((cubit.state as AuthFailure).errorMessage, 'Sign-in failed');
      expect(await session.getToken(), 'existing-test-session');
      api.handler = () async => authJson();
      await cubit.loginWithGoogle();
      expect(cubit.state, isA<AuthSuccess>());
      await cubit.close();
    });
  }
  test(
    'duplicate Google taps and concurrent password login are suppressed',
    () async {
      final pending = Completer<String?>();
      final google = FakeGoogle()..handler = () => pending.future;
      final api = FakeApi();
      final cubit = AuthCubit(
        repo: AuthRepo(apiService: api),
        google: google,
      );
      final first = cubit.loginWithGoogle();
      await cubit.loginWithGoogle();
      await cubit.login('test@example.invalid', 'Password1');
      expect(google.calls, 1);
      expect(api.calls, isEmpty);
      pending.complete('google-test-id-token');
      await first;
      expect(api.calls, hasLength(1));
      await cubit.close();
    },
  );
  for (final dispose in [false, true]) {
    test(
      'late backend response cannot commit after ${dispose ? 'disposal' : 'account change'}',
      () async {
        final pending = Completer<dynamic>();
        final dispatched = Completer<void>();
        final api = FakeApi()
          ..handler = () {
            dispatched.complete();
            return pending.future;
          };
        final cubit = AuthCubit(
          repo: AuthRepo(apiService: api),
          google: FakeGoogle(),
        );
        final login = cubit.loginWithGoogle();
        await dispatched.future;
        if (dispose) {
          await cubit.close();
        } else {
          await session.saveToken('new-account');
        }
        pending.complete(authJson());
        await login;
        expect(await session.getToken(), dispose ? null : 'new-account');
        if (!dispose) await cubit.close();
      },
    );
  }
  test(
    'malformed successful response never overwrites an existing session',
    () async {
      await session.saveToken('existing-test-session');
      final api = FakeApi()
        ..handler = () async => {
          'data': {'token': ''},
        };
      final cubit = AuthCubit(
        repo: AuthRepo(apiService: api),
        google: FakeGoogle(),
      );
      await cubit.loginWithGoogle();
      expect(cubit.state, isA<AuthFailure>());
      expect(await session.getToken(), 'existing-test-session');
      await cubit.close();
    },
  );
  test(
    'email password login and validation retain existing behavior',
    () async {
      final api = FakeApi();
      final cubit = AuthCubit(repo: AuthRepo(apiService: api));
      expect(cubit.validateEmail('bad'), isNotNull);
      expect(cubit.validatePassword('short'), isNotNull);
      await cubit.login('test@example.invalid', 'Password1');
      expect(api.calls, ['login']);
      expect(api.body!['email'], 'test@example.invalid');
      expect(cubit.state, isA<AuthSuccess>());
      expect(await session.getToken(), 'travibe-test-token');
      await cubit.close();
    },
  );
  test(
    'email login retains backend verification requirement and chosen language',
    () async {
      await session.saveLanguage('ar');
      final api = FakeApi()..handler = () async => authJson(verify: true);
      final cubit = AuthCubit(repo: AuthRepo(apiService: api));
      await cubit.login('test@example.invalid', 'Password1');
      expect(
        (cubit.state as AuthSuccess).response!.emailVerificationRequired,
        true,
      );
      expect(session.language.value, 'ar');
      await cubit.close();
    },
  );
  test(
    'registration preserves selected locale and backend verification requirement',
    () async {
      await session.saveLanguage('ar');
      final api = FakeApi()..handler = () async => authJson(verify: true);
      final result = await AuthRepo(apiService: api).register(
        email: 'test@example.invalid',
        password: 'Password1',
        passwordConfirmation: 'Password1',
        termsAccepted: true,
        locale: session.getLanguage(),
      );
      expect(api.calls, ['register']);
      expect(api.body!['locale'], 'ar');
      expect(api.body!['terms_accepted'], true);
      expect(result.emailVerificationRequired, true);
      expect(session.getLanguage(), 'ar');
      expect(await session.getToken(), 'travibe-test-token');
    },
  );
}
