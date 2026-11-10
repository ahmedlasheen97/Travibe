import '../../core/places/fake_city_places.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/auth/cubit/sign_out_cubit.dart';
import 'package:travibe/features/profile/cubit/account_deletion_cubit.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';
import 'package:travibe/features/auth/screens/login_screen.dart';
import 'package:travibe/features/profile/screens/settings_screen.dart';
import 'package:travibe/features/profile/screens/session_exit.dart';
import 'package:travibe/features/profile/widgets/logout_dialog_widget.dart';
import 'package:travibe/features/buddies/cubit/buddies_search_cubit.dart';
import 'package:travibe/features/buddies/data/buddies_repo.dart';
import 'package:travibe/features/home/cubit/posts_cubit.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'account_deletion_test.dart' as account;
import 'settings_privacy_test.dart' as settings;
import '../buddies/buddies_home_test.dart' as buddies;
import '../buddies/buddies_search_test.dart' as search;
import '../home/home_experience_fixtures.dart' as feeds;

class LogoutRepo extends AuthRepo {
  int calls = 0;
  bool revoked = true;
  Object? error;
  Completer<bool>? pending;
  @override
  Future<bool> logout() async {
    calls++;
    if (pending != null) return pending!.future;
    if (error != null) throw error!;
    return revoked;
  }
}

void main() {
  final preferences = PreferencesManager();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.saveToken('account-action-test');
    ScreenUtil.configure(
      data: const MediaQueryData(size: Size(390, 844)),
      designSize: const Size(390, 844),
      minTextAdapt: false,
      splitScreenMode: false,
    );
  });
  tearDown(() => preferences.clear());
  test(
    'POST logout revokes the current bearer token and accepts only 204',
    () async {
      final harness = account.AccountHarness();
      harness.adapter.handler = (request) async {
        expect(request.method, 'POST');
        expect(request.path, 'logout');
        expect(request.queryParameters, isEmpty);
        expect(request.data, isNull);
        expect(request.headers.containsKey('Authorization'), true);
        expect(request.followRedirects, false);
        return ResponseBody.fromString('', 204);
      };
      expect(await AuthRepo(apiService: harness.api).logout(), true);
      expect(harness.adapter.calls, 1);
    },
  );
  test(
    '401 logout identifies an already-invalid token without claiming revocation',
    () async {
      final harness = account.AccountHarness();
      harness.adapter.handler = (_) async => account.accountResponse(401);
      expect(await AuthRepo(apiService: harness.api).logout(), false);
    },
  );
  test('unexpected HTTP 200 does not claim token revocation', () async {
    final harness = account.AccountHarness();
    await expectLater(
      AuthRepo(apiService: harness.api).logout(),
      throwsA(isA<ApiError>()),
    );
  });
  test(
    'successful signout clears user caches and currency while preserving language',
    () async {
      await preferences.completeOnboarding();
      await preferences.saveLanguage('ar');
      await preferences.saveCurrency('AED');
      await preferences.setString('recent_searches', 'private');
      final repo = LogoutRepo();
      final cubit = SignOutCubit(repo: repo);
      await cubit.submit();
      expect(cubit.state.signedOut, true);
      expect(cubit.state.revoked, true);
      expect(preferences.hasSession, false);
      expect(preferences.getString('recent_searches'), isNull);
      expect(preferences.onboardingCompleted, true);
      expect(preferences.language.value, 'ar');
      expect(preferences.getString('selected_language'), 'ar');
      expect(preferences.currency.value, isNull);
      await cubit.close();
    },
  );
  test(
    'already invalid token safely exits locally and reports revoked false',
    () async {
      final cubit = SignOutCubit(repo: LogoutRepo()..revoked = false);
      await cubit.submit();
      expect(cubit.state.signedOut, true);
      expect(cubit.state.revoked, false);
      expect(preferences.hasSession, false);
      await cubit.close();
    },
  );
  test(
    'network/server revocation failure retains session and supports explicit retry',
    () async {
      final repo = LogoutRepo()..error = ApiError(message: 'Unreachable');
      final cubit = SignOutCubit(repo: repo);
      await cubit.submit();
      expect(preferences.hasSession, true);
      expect(cubit.state.signedOut, false);
      expect(cubit.state.loading, false);
      expect(cubit.state.error, contains('still signed in'));
      expect(repo.calls, 1);
      await Future<void>.delayed(Duration.zero);
      expect(repo.calls, 1);
      repo.error = null;
      await cubit.submit();
      expect(repo.calls, 2);
      expect(cubit.state.signedOut, true);
      await cubit.close();
    },
  );
  test('duplicate signout submissions share one backend operation', () async {
    final repo = LogoutRepo()..pending = Completer<bool>();
    final cubit = SignOutCubit(repo: repo);
    final pending = cubit.submit();
    await cubit.submit();
    expect(repo.calls, 1);
    repo.pending!.complete(true);
    await pending;
    expect(cubit.state.signedOut, true);
    await cubit.close();
  });
  test(
    'logout response from a previous account cannot clear the new session',
    () async {
      final repo = LogoutRepo()..pending = Completer<bool>();
      final cubit = SignOutCubit(repo: repo);
      final pending = cubit.submit();
      await preferences.saveToken('replacement-account');
      repo.pending!.complete(true);
      await pending;
      expect(await preferences.getToken(), 'replacement-account');
      expect(cubit.state.signedOut, false);
      await cubit.close();
    },
  );
  test(
    'session switch before dispatch prevents revoking the replacement token',
    () async {
      final harness = account.AccountHarness();
      harness.client.dio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            await preferences.saveToken('replacement-account');
            handler.next(options);
          },
        ),
      );
      await expectLater(
        AuthRepo(apiService: harness.api).logout(),
        throwsA(isA<ApiError>()),
      );
      expect(harness.adapter.calls, 0);
    },
  );
  test(
    'late feed and search responses cannot repopulate cleared account state',
    () async {
      final feedRepo = feeds.EmptyPostsRepo()..followingGate = Completer();
      final posts = PostsCubit(postsRepo: feedRepo, feed: FeedType.following);
      final feed = posts.loadPosts();
      final api = buddies.FakeApi(Completer<dynamic>());
      final discovery = BuddiesSearchCubit(repo: BuddiesRepo(apiService: api));
      discovery.selectCity(testCity('Cairo'));
      final cubit = SignOutCubit(repo: LogoutRepo());
      await cubit.submit();
      (api.result as Completer<dynamic>).complete(search.searchPage(ids: [1]));
      feedRepo.followingGate!.complete(
        await feeds.EmptyPostsRepo().getPosts(feed: FeedType.following),
      );
      await feed;
      await Future<void>.delayed(Duration.zero);
      expect(discovery.state.items, isEmpty);
      expect(discovery.state.selectedCity, isNull);
      expect(posts.state, isA<PostsInitial>());
      await posts.close();
      await discovery.close();
      await cubit.close();
    },
  );
  test(
    'confirmed deletion clears private preferences and preserves app language',
    () async {
      await preferences.completeOnboarding();
      await preferences.saveLanguage('ar');
      await preferences.setString('private-history', 'test-private');
      final cubit = AccountDeletionCubit(repo: account.MockAccountRepo());
      await cubit.submit('test-only-password', confirmed: true);
      expect(cubit.state.deleted, true);
      expect(preferences.getString('private-history'), isNull);
      expect(preferences.onboardingCompleted, true);
      expect(preferences.language.value, 'ar');
      expect(preferences.getString('selected_language'), 'ar');
      await cubit.close();
    },
  );
  test(
    'disposing signout during a request ignores a late failure safely',
    () async {
      final repo = LogoutRepo()..pending = Completer<bool>();
      final cubit = SignOutCubit(repo: repo);
      final request = cubit.submit();
      await cubit.close();
      repo.pending!.completeError(ApiError(message: 'Offline'));
      await request;
      expect(repo.calls, 1);
      expect(preferences.hasSession, true);
    },
  );
  test(
    'disposing deletion during a request does not retry or expose its error',
    () async {
      final repo = account.MockAccountRepo()..pending = Completer<void>();
      final cubit = AccountDeletionCubit(repo: repo);
      final request = cubit.submit('test-only-password', confirmed: true);
      await cubit.close();
      repo.pending!.completeError(StateError('private-error'));
      await request;
      expect(repo.calls, 1);
      expect(preferences.hasSession, true);
    },
  );

  testWidgets('confirmation and Cancel perform no logout request', (
    tester,
  ) async {
    final repo = LogoutRepo();
    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showLogOutDialogWidget(context, authRepo: repo),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(
      find.text('Are you sure you want to log out of Travibe?'),
      findsOneWidget,
    );
    expect(repo.calls, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.calls, 0);
    expect(preferences.hasSession, true);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'signout has one compact primary Cupertino loader and prevents duplicates',
    (tester) async {
      final repo = LogoutRepo()..pending = Completer<bool>();
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    showLogOutDialogWidget(context, authRepo: repo),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Log Out'));
      await tester.pump();
      await tester.pump();
      expect(repo.calls, 1);
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(
        tester
            .widget<CupertinoActivityIndicator>(
              find.byType(CupertinoActivityIndicator),
            )
            .color,
        DarkColors.primaryColor,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
            .onPressed,
        isNull,
      );
      repo.pending!.completeError(ApiError(message: 'Offline'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(preferences.hasSession, true);
      expect(find.textContaining('still signed in'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Settings signs out to Login and removes authenticated Back navigation',
    (tester) async {
      final user = settings.settingsCubit(settings.SettingsApi());
      final repo = LogoutRepo();
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: SettingsScreen(currentUser: user, authRepo: repo),
        ),
      );
      await tester.pumpAndSettle();
      await settings.tapVisible(tester, find.text('Log Out'));
      await tester.tap(find.widgetWithText(TextButton, 'Log Out'));
      await tester.pumpAndSettle();
      expect(repo.calls, 1);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
        Navigator.of(tester.element(find.byType(LoginScreen))).canPop(),
        false,
      );
      expect(user.state.profile, isNull);
      await tester.pumpWidget(const SizedBox());
      await user.close();
    },
  );
  for (final initial in ['/root', '/login']) {
    testWidgets(
      'session exit clears router and imperative routes from $initial',
      (tester) async {
        Widget exit(BuildContext context) => Scaffold(
          body: TextButton(
            onPressed: () => openSignedOutScreen(context),
            child: const Text('Exit'),
          ),
        );
        final router = GoRouter(
          initialLocation: initial,
          routes: [
            GoRoute(path: '/root', builder: (context, _) => exit(context)),
            GoRoute(
              path: '/login',
              builder: (context, _) => const LoginScreen(),
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp.router(theme: darkTheme, routerConfig: router),
        );
        await tester.pumpAndSettle();
        if (initial == '/login') {
          final context = tester.element(find.byType(LoginScreen));
          Navigator.of(
            context,
          ).pushReplacement(MaterialPageRoute<void>(builder: exit));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Exit'));
        await tester.pumpAndSettle();
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(find.text('Exit'), findsNothing);
        expect(
          Navigator.of(tester.element(find.byType(LoginScreen))).canPop(),
          false,
        );
        await tester.pumpWidget(const SizedBox());
        router.dispose();
      },
    );
  }
}
