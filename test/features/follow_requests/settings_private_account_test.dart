import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow_requests/cubit/incoming_requests_cubit.dart';
import 'package:travibe/features/follow_requests/screens/follow_requests_screen.dart';
import 'package:travibe/features/profile/cubit/profile_cubit.dart';
import 'package:travibe/features/profile/data/profile_repo.dart';
import 'package:travibe/features/profile/data/settings_update.dart';
import 'package:travibe/features/profile/screens/settings_screen.dart';

import '../profile/settings_privacy_test.dart'
    show SettingsApi, settingsCubit, settingsUser;
import 'follow_requests_fakes.dart';

void main() {
  late FollowCubit follow;
  setUp(() async {
    ScreenUtil.configure(
      data: const MediaQueryData(size: Size(390, 844)),
      designSize: const Size(390, 844),
      splitScreenMode: false,
      minTextAdapt: false,
    );
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('settings-session');
    follow = FollowCubit();
  });
  tearDown(() async {
    await follow.close();
    await PreferencesManager().clear();
  });

  Future<(SettingsApi, FakeFollowRequestsRepo)> show(
    WidgetTester tester, {
    bool private = false,
    List<int> pending = const [],
  }) async {
    final api = SettingsApi()
      ..user = {...settingsUser(), 'is_private': private};
    final user = settingsCubit(api);
    addTearDown(user.close);
    final repo = FakeFollowRequestsRepo(pages: {1: requestsPage(pending)});
    final incoming = IncomingRequestsCubit(repo: repo, follow: follow);
    addTearDown(incoming.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        home: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: follow),
            BlocProvider.value(value: incoming),
          ],
          child: SettingsScreen(currentUser: user),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (api, repo);
  }

  Finder privateSwitch() => find.descendant(
    of: find
        .ancestor(of: find.text('Private Account'), matching: find.byType(Row))
        .first,
    matching: find.byType(Switch),
  );

  test('is_private is an accepted settings key', () {
    expect(SettingsUpdate({'is_private': true}).toJson(), {'is_private': true});
    expect(() => SettingsUpdate({'is_private': 'yes'}), throwsA(anything));
  });

  testWidgets(
    'turning private on sends PATCH is_private and shows requests row',
    (tester) async {
      final (api, _) = await show(tester);
      expect(find.text('Follow Requests'), findsNothing);
      expect(tester.widget<Switch>(privateSwitch()).value, isFalse);
      await tester.tap(privateSwitch());
      await tester.pumpAndSettle();
      expect(api.patches.single, {'is_private': true});
      expect(find.text('Switch to public?'), findsNothing);
      expect(tester.widget<Switch>(privateSwitch()).value, isTrue);
      expect(find.text('Follow Requests'), findsOneWidget);
    },
  );

  testWidgets('turning private off asks first; cancel sends nothing', (
    tester,
  ) async {
    final (api, _) = await show(tester, private: true);
    await tester.tap(privateSwitch());
    await tester.pumpAndSettle();
    expect(find.text('Switch to public?'), findsOneWidget);
    expect(
      find.text('All pending follow requests will be accepted.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.patches, isEmpty);
    expect(tester.widget<Switch>(privateSwitch()).value, isTrue);

    await tester.tap(privateSwitch());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch to public'));
    await tester.pumpAndSettle();
    expect(api.patches.single, {'is_private': false});
    expect(tester.widget<Switch>(privateSwitch()).value, isFalse);
  });

  testWidgets('requests row shows the pending count and opens the list', (
    tester,
  ) async {
    await show(tester, private: true, pending: [3, 4]);
    final row = find.ancestor(
      of: find.text('Follow Requests'),
      matching: find.byType(InkWell),
    );
    expect(
      find.descendant(of: row.first, matching: find.text('2')),
      findsOneWidget,
    );
    await tester.tap(find.text('Follow Requests'));
    await tester.pumpAndSettle();
    expect(find.byType(FollowRequestsScreen), findsOneWidget);
    expect(find.text('User 3'), findsOneWidget);
  });

  testWidgets('public account with leftover requests still shows the row', (
    tester,
  ) async {
    await show(tester, pending: [3]);
    expect(find.text('Follow Requests'), findsOneWidget);
  });

  test('accepting a request bumps my followers on the own profile', () async {
    final api = SettingsApi()
      ..user = {...settingsUser(), 'followers_count': 12};
    final user = settingsCubit(api);
    addTearDown(user.close);
    await user.load();
    final own = ProfileCubit(
      currentUser: user,
      profileRepo: ProfileRepo(apiService: api),
    );
    addTearDown(own.close);
    expect((own.state as ProfileLoaded).profile.followersCount, 12);
    user.adjustFollowersCount(1);
    await Future<void>.delayed(Duration.zero);
    expect(user.state.profile?.followersCount, 13);
    expect((own.state as ProfileLoaded).profile.followersCount, 13);
    user.adjustFollowersCount(-1);
    await Future<void>.delayed(Duration.zero);
    expect((own.state as ProfileLoaded).profile.followersCount, 12);
  });
}
