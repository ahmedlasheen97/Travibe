import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/home/cubit/home_account_cubit.dart';
import 'package:travibe/features/home/data/home_account_cache.dart';
import 'package:travibe/features/home/data/home_account_repo.dart';
import 'package:travibe/features/home/screens/home_screen.dart';
import 'package:travibe/features/home/widgets/home_top_bar.dart';
import 'home_experience_fixtures.dart';

class NamedAccountRepo extends AccountRepo {
  String name = 'ahmed lasheen';
  @override
  Future<HomeAccount> getAccount() async {
    calls++;
    if (error != null) throw error!;
    return HomeAccount(id: '1', name: name, followingCount: 0);
  }
}

void main() {
  final preferences = PreferencesManager();
  final offline = ApiError(message: 'offline', isConnectionError: true);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.saveToken('token-a');
  });
  tearDown(() => preferences.clear());

  Future<void> loadOnce(NamedAccountRepo repo) async {
    final cubit = HomeAccountCubit(repo: repo);
    await cubit.load();
    await cubit.close();
    // Let the best-effort cache write finish.
    await Future<void>.delayed(Duration.zero);
  }

  test('a loaded account is cached and seeds the next cubit offline', () async {
    final repo = NamedAccountRepo();
    await loadOnce(repo);
    repo.error = offline;
    final cubit = HomeAccountCubit(repo: repo);
    expect(cubit.state.account?.name, 'ahmed lasheen');
    await cubit.load();
    expect(cubit.state.status, HomeAccountStatus.failure);
    expect(cubit.state.account?.name, 'ahmed lasheen');
    // The cached count is never a verified relationship count.
    expect(cubit.state.hasVerifiedCount, isFalse);
    await cubit.close();
  });

  test('another account never reads the cache', () async {
    await loadOnce(NamedAccountRepo());
    await preferences.saveToken('token-b');
    expect(HomeAccountCache().read(), isNull);
    expect(HomeAccountCubit(repo: NamedAccountRepo()).state.account, isNull);
  });

  test('a session switch reseeds instead of keeping the old name', () async {
    final repo = NamedAccountRepo();
    final cubit = HomeAccountCubit(repo: repo);
    await cubit.load();
    await preferences.saveToken('token-b');
    repo.error = offline;
    await cubit.load(force: true);
    expect(cubit.state.account, isNull);
    await cubit.close();
  });

  test('logout removes the cached account', () async {
    await loadOnce(NamedAccountRepo());
    expect(preferences.getString(HomeAccountCache.key), isNotNull);
    await preferences.clearSession();
    expect(preferences.getString(HomeAccountCache.key), isNull);
  });

  group('greeting', () {
    Future<void> pumpBar(WidgetTester tester, HomeTopBar bar) =>
        tester.pumpWidget(
          ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, _) => MaterialApp(home: Scaffold(body: bar)),
          ),
        );

    String greeting(WidgetTester tester) =>
        tester.widget<RichText>(find.byType(RichText).first).text.toPlainText();

    testWidgets('a signed-in user without a name is never "there"', (
      tester,
    ) async {
      await pumpBar(
        tester,
        HomeTopBar(
          signedIn: true,
          onMessagesTap: () {},
          onNotificationsTap: () {},
        ),
      );
      expect(greeting(tester), 'Hello');
      await pumpBar(
        tester,
        HomeTopBar(onMessagesTap: () {}, onNotificationsTap: () {}),
      );
      expect(greeting(tester), 'Hello, there');
    });

    testWidgets('Home greets with the cached name when offline on cold start', (
      tester,
    ) async {
      final repo = NamedAccountRepo();
      await tester.runAsync(() => loadOnce(repo));
      repo.error = offline;
      final people = PeopleRepo(repo)..listError = offline;
      final follow = FollowCubit(repo: people);
      final block = BlockCubit(follow: follow);
      addTearDown(block.close);
      addTearDown(follow.close);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            theme: darkTheme,
            home: Scaffold(
              body: MultiBlocProvider(
                providers: [
                  BlocProvider.value(value: follow),
                  BlocProvider.value(value: block),
                ],
                child: HomeScreen(
                  accountRepo: repo,
                  postsRepo: EmptyPostsRepo()..error = offline,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(greeting(tester), 'Hello, ahmed');
      expect(find.textContaining('there'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
