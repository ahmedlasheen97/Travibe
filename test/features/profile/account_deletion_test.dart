import 'package:travibe/core/widgets/glass_confirm_dialog.dart';
import 'package:travibe/core/widgets/glass_surface.dart';
import 'package:flutter/cupertino.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/core/datasource/remotedata/dio_client.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/profile/cubit/account_deletion_cubit.dart';
import 'package:travibe/features/profile/data/account_repo.dart';
import 'package:travibe/features/profile/screens/delete_account_screen.dart';
import 'package:travibe/features/auth/screens/login_screen.dart';
import 'package:travibe/features/buddies/cubit/buddies_cubit.dart';
import 'package:travibe/features/buddies/data/buddies_repo.dart';
import '../buddies/buddies_home_test.dart' as buddies;
import 'settings_privacy_test.dart' as settings;

class AccountAdapter implements HttpClientAdapter {
  late Future<ResponseBody> Function(RequestOptions) handler;
  int calls = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody accountResponse(
  int status, {
  dynamic body = const {'message': 'Account deleted successfully.'},
}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

class AccountHarness {
  AccountHarness({ApiRequestObserver? observer}) {
    client.dio.httpClientAdapter = adapter;
    adapter.handler = (_) => Future.value(accountResponse(200));
    api = ApiService(client: client, observer: observer);
    repo = AccountRepo(apiService: api);
  }
  final client = DioClient();
  final adapter = AccountAdapter();
  late final ApiService api;
  late final AccountRepo repo;
}

class MockAccountRepo extends AccountRepo {
  int calls = 0;
  AccountDeletionFailure? failure;
  Completer<void>? pending;
  @override
  Future<void> delete(String password) async {
    calls++;
    if (pending != null) await pending!.future;
    if (failure != null) throw failure!;
  }
}

class DisposalProbe extends StatefulWidget {
  const DisposalProbe({
    super.key,
    required this.child,
    required this.onDispose,
  });
  final Widget child;
  final VoidCallback onDispose;
  @override
  State<DisposalProbe> createState() => _DisposalProbeState();
}

class _DisposalProbeState extends State<DisposalProbe> {
  @override
  Widget build(BuildContext context) => widget.child;
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }
}

Future<void> showDelete(
  WidgetTester tester,
  AccountRepo repo, {
  VoidCallback? onDispose,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: darkTheme,
      home: DisposalProbe(
        onDispose: onDispose ?? () {},
        child: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => DeleteAccountScreen(repo: repo),
                ),
              ),
              child: const Text('Open delete'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open delete'));
  await tester.pumpAndSettle();
}

Future<void> confirmDelete(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField), 'test-only-password');
  await tester.tap(find.byType(CheckboxListTile));
  await tester.tap(find.text('Delete my Account'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Delete Permanently'));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final preferences = PreferencesManager();
  setUp(() async {
    ScreenUtil.configure(
      data: const MediaQueryData(size: Size(390, 844)),
      designSize: const Size(390, 844),
      splitScreenMode: false,
      minTextAdapt: false,
    );
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.saveToken('delete-test-session');
  });
  tearDown(() => preferences.clear());

  test(
    'DELETE uses only the required password query, Bearer auth, no body or redirects',
    () async {
      final transport = AccountHarness();
      const secret = 'test-only p@ss &?/';
      transport.adapter.handler = (options) async {
        expect(options.method, 'DELETE');
        expect(options.path, 'account');
        expect(options.data, isNull);
        expect(options.queryParameters.keys, ['password']);
        expect(options.queryParameters['password'] == secret, true);
        expect(options.headers.containsKey('Authorization'), true);
        expect(options.followRedirects, false);
        expect(options.extra['sensitiveAccountDeletion'], true);
        return accountResponse(200);
      };
      await transport.repo.delete(secret);
      expect(transport.adapter.calls, 1);
    },
  );

  test('password is required before any request', () async {
    final transport = AccountHarness();
    await expectLater(
      transport.repo.delete(''),
      throwsA(isA<AccountDeletionFailure>()),
    );
    expect(transport.adapter.calls, 0);
  });

  test(
    'a session switch before dispatch prevents DELETE from using another account token',
    () async {
      final transport = AccountHarness();
      transport.client.dio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            await preferences.saveToken('replacement-session');
            handler.next(options);
          },
        ),
      );
      await expectLater(
        transport.repo.delete('test-only-password'),
        throwsA(isA<AccountDeletionFailure>()),
      );
      expect(transport.adapter.calls, 0);
      expect(await preferences.getToken(), 'replacement-session');
    },
  );

  test(
    'confirmation is required and duplicate submissions are suppressed',
    () async {
      final repo = MockAccountRepo()..pending = Completer<void>();
      final cubit = AccountDeletionCubit(repo: repo);
      addTearDown(cubit.close);
      await cubit.submit('test-only-password', confirmed: false);
      expect(repo.calls, 0);
      expect(preferences.hasSession, true);
      await cubit.submit('', confirmed: true);
      expect(repo.calls, 0);
      final first = cubit.submit('test-only-password', confirmed: true);
      await cubit.submit('test-only-password', confirmed: true);
      expect(repo.calls, 1);
      repo.pending!.complete();
      await first;
      expect(cubit.state.deleted, true);
    },
  );

  for (final status in [401, 422]) {
    test(
      'HTTP $status preserves session and maps a safe fixed error',
      () async {
        final transport = AccountHarness();
        const secret = 'test-only-private-password';
        transport.adapter.handler = (_) async => accountResponse(
          status,
          body: {
            'message': secret,
            'errors': {
              'password': [secret],
            },
          },
        );
        final cubit = AccountDeletionCubit(repo: transport.repo);
        addTearDown(cubit.close);
        await cubit.submit(secret, confirmed: true);
        expect(preferences.hasSession, true);
        expect(cubit.state.deleted, false);
        expect(cubit.state.error!.statusCode, status);
        expect(cubit.state.error.toString().contains(secret), false);
        expect(cubit.state.error!.outcomeUncertain, false);
      },
    );
  }

  for (final status in [200, 202, 204, 500]) {
    test(
      'HTTP $status without exact confirmed success never clears the session',
      () async {
        final transport = AccountHarness();
        transport.adapter.handler = (_) async => accountResponse(
          status,
          body: status == 200
              ? {'message': 'Something else'}
              : {'message': 'Account deleted successfully.'},
        );
        final cubit = AccountDeletionCubit(repo: transport.repo);
        addTearDown(cubit.close);
        await cubit.submit('test-only-password', confirmed: true);
        expect(cubit.state.deleted, false);
        expect(preferences.hasSession, true);
        expect(cubit.state.error!.outcomeUncertain, true);
      },
    );
  }

  test(
    'network interruption is uncertain, preserves session and never automatically retries',
    () async {
      final transport = AccountHarness();
      transport.adapter.handler = (options) async => throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      );
      final cubit = AccountDeletionCubit(repo: transport.repo);
      addTearDown(cubit.close);
      await cubit.submit('test-only-password', confirmed: true);
      expect(cubit.state.error!.outcomeUncertain, true);
      expect(preferences.hasSession, true);
      await cubit.submit('test-only-password', confirmed: true);
      expect(transport.adapter.calls, 1);
    },
  );

  test(
    'password and URL never reach observers/logs/errors and request metadata is redacted',
    () async {
      const secret = 'test-only-secret-with-characters';
      var observations = 0;
      final logs = <String>[];
      RequestOptions? captured;
      final oldDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      try {
        await runZoned(
          () async {
            final transport = AccountHarness(
              observer: (_, _, _, _, _) => observations++,
            );
            transport.adapter.handler = (options) async {
              captured = options;
              return accountResponse(
                422,
                body: {
                  'message': secret,
                  'errors': {
                    'password': [secret],
                  },
                },
              );
            };
            try {
              await transport.repo.delete(secret);
            } on AccountDeletionFailure catch (error) {
              expect(error.toString().contains(secret), false);
            }
          },
          zoneSpecification: ZoneSpecification(
            print: (_, _, _, line) => logs.add(line),
          ),
        );
        expect(observations, 0);
        expect(logs.any((line) => line.contains(secret)), false);
        expect(captured!.queryParameters, isEmpty);
        expect(captured!.uri.toString().contains(secret), false);
      } finally {
        debugPrint = oldDebugPrint;
      }
    },
  );

  test(
    'only confirmed HTTP 200 success clears preferences, current user and Buddies state',
    () async {
      final settingsApi = settings.SettingsApi();
      final user = settings.settingsCubit(settingsApi);
      addTearDown(user.close);
      await user.load();
      final home = buddies.FakeApi(buddies.home());
      final discovery = BuddiesCubit(
        repo: BuddiesRepo(apiService: home),
        currentUser: user,
      );
      addTearDown(discovery.close);
      await discovery.load();
      await preferences.setString('user-specific-cache', 'test-cache');
      final session = preferences.sessionRevision;
      final transport = AccountHarness();
      final cubit = AccountDeletionCubit(repo: transport.repo);
      addTearDown(cubit.close);
      await cubit.submit('test-only-password', confirmed: true);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.deleted, true);
      expect(preferences.hasSession, false);
      expect(preferences.getString('user-specific-cache'), isNull);
      expect(preferences.sessionRevision, greaterThan(session));
      expect(user.state.profile, isNull);
      expect(discovery.state.home, isNull);
      expect(preferences.language.value, 'en');
      expect(preferences.currency.value, isNull);
    },
  );

  test(
    'late deletion response from another session cannot sign out a new account',
    () async {
      final repo = MockAccountRepo()..pending = Completer<void>();
      final cubit = AccountDeletionCubit(repo: repo);
      addTearDown(cubit.close);
      final pending = cubit.submit('test-only-password', confirmed: true);
      await preferences.saveToken('new-account-session');
      repo.pending!.complete();
      await pending;
      expect(await preferences.getToken(), 'new-account-session');
      expect(cubit.state.deleted, false);
      expect(cubit.state.sessionChanged, true);
    },
  );

  testWidgets(
    'opening does not delete; password and explicit consent precede the final dialog',
    (tester) async {
      final repo = MockAccountRepo();
      await showDelete(tester, repo);
      expect(repo.calls, 0);
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        true,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).autofillHints,
        isEmpty,
      );
      await tester.tap(find.text('Delete my Account'));
      await tester.pumpAndSettle();
      expect(find.text('Please enter your current password'), findsOneWidget);
      expect(repo.calls, 0);
      await tester.enterText(find.byType(TextFormField), 'test-only-password');
      await tester.tap(find.text('Delete my Account'));
      await tester.pumpAndSettle();
      expect(
        find.text('Confirm permanent account deletion before continuing.'),
        findsOneWidget,
      );
      expect(repo.calls, 0);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        false,
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.tap(find.text('Delete my Account'));
      await tester.pumpAndSettle();
      expect(find.text('Permanently Delete Account?'), findsOneWidget);
      expect(find.byType(GlassConfirmDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(GlassConfirmDialog),
          matching: find.byType(GlassSurface),
        ),
        findsOneWidget,
      );
      expect(repo.calls, 0);
      await tester.tap(find.widgetWithText(TextButton, 'Keep Account').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
      expect(repo.calls, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'confirmed success removes authenticated routes and navigates to Login without Back',
    (tester) async {
      final repo = MockAccountRepo();
      var disposed = false;
      await showDelete(tester, repo, onDispose: () => disposed = true);
      await confirmDelete(tester);
      await tester.pumpAndSettle();
      expect(repo.calls, 1);
      expect(preferences.hasSession, false);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(DeleteAccountScreen), findsNothing);
      expect(disposed, true);
      expect(
        Navigator.of(tester.element(find.byType(LoginScreen))).canPop(),
        false,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'processing blocks duplicate submission; password clears and validation failure keeps session',
    (tester) async {
      final repo = MockAccountRepo()
        ..pending = Completer<void>()
        ..failure = AccountDeletionFailure(
          message: 'The password was not accepted.',
          statusCode: 422,
        );
      await showDelete(tester, repo);
      await confirmDelete(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      expect(
        tester.widget<BackButtonWidget>(find.byType(BackButtonWidget)).enabled,
        false,
      );
      expect(repo.calls, 1);
      repo.pending!.complete();
      await tester.pumpAndSettle();
      expect(preferences.hasSession, true);
      expect(find.text('The password was not accepted.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'uncertain outcome disables resubmission and Cancel safely returns without clearing session',
    (tester) async {
      final repo = MockAccountRepo()
        ..failure = AccountDeletionFailure.uncertain();
      await showDelete(tester, repo);
      await confirmDelete(tester);
      await tester.pumpAndSettle();
      expect(preferences.hasSession, true);
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      expect(find.textContaining('could not be confirmed'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(DeleteAccountScreen), findsNothing);
      expect(preferences.hasSession, true);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'deletion form and final confirmation fit narrow screens with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = MockAccountRepo();
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: DeleteAccountScreen(repo: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byType(TextFormField),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byType(TextFormField), 'test-only-password');
      await tester.scrollUntilVisible(
        find.byType(Checkbox),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.tap(find.text('Delete my Account'));
      await tester.pumpAndSettle();
      expect(find.byType(GlassConfirmDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(repo.calls, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
