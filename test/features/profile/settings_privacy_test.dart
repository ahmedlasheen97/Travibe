import 'package:travibe/core/notifications/firebase_messaging_client.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/constants/feature_flags.dart';
import 'package:travibe/core/widgets/sheet_handle.dart';
import 'package:travibe/core/widgets/glass_surface.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';
import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'package:travibe/features/profile/data/profile_repo.dart';
import 'package:travibe/features/profile/data/settings_repo.dart';
import 'package:travibe/features/profile/data/settings_update.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/cubit/profile_cubit.dart';
import 'package:travibe/features/profile/screens/settings_screen.dart';
import 'package:travibe/features/profile/screens/currency_screen.dart';
import 'package:travibe/features/auth/screens/login_screen.dart';
import 'package:travibe/features/profile/widgets/language_bottom_sheet.dart';
import 'package:travibe/features/buddies/cubit/buddies_cubit.dart';
import 'package:travibe/features/buddies/data/buddies_repo.dart';
import 'package:travibe/features/buddies/screens/buddies_screen.dart';
import 'package:travibe/features/buddies/widgets/buddies_visibility_invitation.dart';
import 'package:travibe/main.dart' as app;
import '../buddies/buddies_home_test.dart' as buddies;
import 'package:travibe/core/notifications/push_notification_service.dart';
import '../../core/notifications/push_fakes.dart';

Map<String, dynamic> settingsUser({int id = 7, bool visible = false}) => {
  'id': id,
  'name': 'Real API name',
  'locale': 'en',
  'currency_code': 'AED',
  'show_active_status': true,
  'show_in_travel_buddy': visible,
  'push_notifications_enabled': true,
};

class SettingsApi extends ApiService {
  @override
  Future<bool> revokeCurrentToken() async => true;
  Map<String, dynamic> user = settingsUser();
  dynamic patchResult;
  dynamic readResult;
  final patches = <Map<String, dynamic>>[];
  final reads = <String>[];
  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
    expect(endpoint, 'profile');
    reads.add(endpoint);
    if (readResult is Completer<dynamic>) {
      return (readResult as Completer<dynamic>).future;
    }
    if (readResult is ApiError) throw readResult as ApiError;
    return readResult ?? {'data': Map<String, dynamic>.from(user)};
  }

  @override
  Future<dynamic> patch(String endpoint, Map<String, dynamic> data) async {
    expect(endpoint, 'settings');
    patches.add(Map.of(data));
    if (patchResult is Completer<dynamic>) {
      return (patchResult as Completer<dynamic>).future;
    }
    if (patchResult is ApiError) throw patchResult as ApiError;
    if (patchResult != null) return patchResult;
    user = {...user, ...data};
    return {'data': Map<String, dynamic>.from(user)};
  }
}

CurrentUserCubit settingsCubit(SettingsApi api) => CurrentUserCubit(
  profileRepo: ProfileRepo(apiService: api),
  settingsRepo: SettingsRepo(
    apiService: api,
    supportedCurrencies: {'AED', 'USD'},
  ),
);

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) await tester.scrollUntilVisible(finder, 160);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
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
    await preferences.saveToken('settings-session');
  });
  tearDown(() => preferences.clear());

  test(
    'partial PATCH permits only documented values and preserves nullable currency',
    () async {
      final api = SettingsApi();
      final repo = SettingsRepo(apiService: api);
      for (final entry in {
        'locale': 'ar',
        'currency_code': null,
        'show_active_status': false,
        'show_in_travel_buddy': true,
        'push_notifications_enabled': false,
      }.entries) {
        await repo.update(SettingsUpdate({entry.key: entry.value}));
        expect(api.patches.last, {entry.key: entry.value});
      }
      for (final values in [
        {},
        {'email': 'x'},
        {'locale': 'fr'},
        {'show_active_status': 'true'},
        {'currency_code': 'Egypt'},
        {'currency_code': 'usd'},
      ]) {
        expect(
          () => SettingsUpdate(Map<String, dynamic>.from(values)),
          throwsA(isA<ApiError>()),
        );
      }
    },
  );

  test(
    'UserResource keeps missing settings unknown; invalid confirmations fail visibly',
    () async {
      final absent = ProfileModel.fromJson({'id': 7});
      expect(absent.hasSettings, false);
      expect(absent.showInTravelBuddy, isNull);
      expect(absent.currencyCode, isNull);
      expect(
        ProfileModel.fromJson({
          ...settingsUser(),
          'currency_code': 'invalid',
        }).hasSettings,
        false,
      );
      final api = SettingsApi();
      final repo = SettingsRepo(apiService: api);
      for (final data in [
        {},
        {'id': 7},
        {...settingsUser(), 'show_in_travel_buddy': 'true'},
        {...settingsUser(), 'locale': 'fr'},
        {...settingsUser(), 'currency_code': 123},
      ]) {
        api.patchResult = {'data': data};
        await expectLater(
          repo.update(SettingsUpdate({'show_in_travel_buddy': true})),
          throwsA(isA<ApiError>()),
        );
      }
    },
  );

  test(
    'server values initialize state; each toggle commits only after confirmation',
    () async {
      final api = SettingsApi();
      final user = settingsCubit(api);
      addTearDown(user.close);
      await user.load();
      expect(user.state.profile!.showActiveStatus, true);
      expect(user.state.profile!.showInTravelBuddy, false);
      for (final field in [
        'show_active_status',
        'show_in_travel_buddy',
        'push_notifications_enabled',
      ]) {
        final pending = Completer<dynamic>();
        api.patchResult = pending;
        final before = user.state.profile!;
        final update = user.update(SettingsUpdate({field: false}));
        expect(user.state.saving, field);
        expect(identical(user.state.profile, before), true);
        pending.complete({
          'data': {...settingsUser(), field: false},
        });
        await update;
        expect(user.state.saving, isNull);
        expect(api.patches.last, {field: false});
      }
    },
  );

  test(
    'failed setting changes preserve unrelated settings and presentation preferences',
    () async {
      final api = SettingsApi();
      final user = settingsCubit(api);
      addTearDown(user.close);
      await user.load();
      final before = user.state.profile;
      final failure = ApiError(message: 'Unsupported choice', statusCode: 422);
      api.patchResult = failure;
      await user.update(SettingsUpdate({'locale': 'ar'}));
      expect(identical(user.state.profile, before), true);
      expect(user.state.error, same(failure));
      expect(preferences.getLanguage(), 'en');
      expect(preferences.getCurrency(), 'AED');
      api.patchResult = null;
      await user.update(SettingsUpdate({'show_in_travel_buddy': true}));
      expect(user.state.profile!.showActiveStatus, true);
      expect(user.state.profile!.pushNotificationsEnabled, true);
    },
  );

  test(
    'locale and nullable currency update presentation only after successful API confirmation',
    () async {
      final api = SettingsApi();
      final user = settingsCubit(api);
      addTearDown(user.close);
      await user.load();
      final pending = Completer<dynamic>();
      api.patchResult = pending;
      final updating = user.update(SettingsUpdate({'locale': 'ar'}));
      expect(preferences.language.value, 'en');
      pending.complete({
        'data': {...settingsUser(), 'locale': 'ar'},
      });
      await updating;
      expect(preferences.language.value, 'ar');
      api.patchResult = null;
      api.user = {...settingsUser(), 'locale': 'ar'};
      await user.update(SettingsUpdate({'currency_code': 'USD'}));
      expect(preferences.currency.value, 'USD');
      await user.update(SettingsUpdate({'currency_code': null}));
      expect(preferences.currency.value, isNull);
      expect(preferences.getString('selected_currency'), isNull);
      final count = api.patches.length;
      await user.update(SettingsUpdate({'currency_code': 'XYZ'}));
      expect(api.patches.length, count);
      expect(user.state.error, isNotNull);
    },
  );

  test(
    'conflicting requests are suppressed while one full-resource settings response is pending',
    () async {
      final api = SettingsApi();
      final user = settingsCubit(api);
      addTearDown(user.close);
      await user.load();
      final pending = Completer<dynamic>();
      api.patchResult = pending;
      final first = user.update(SettingsUpdate({'locale': 'ar'}));
      await user.update(SettingsUpdate({'locale': 'en'}));
      await user.update(SettingsUpdate({'show_active_status': false}));
      expect(api.patches, hasLength(1));
      pending.complete({
        'data': {...settingsUser(), 'locale': 'ar'},
      });
      await first;
      expect(user.state.profile!.locale, 'ar');
      expect(user.state.profile!.showActiveStatus, true);
    },
  );

  test('a stale profile read cannot overwrite confirmed settings', () async {
    final api = SettingsApi();
    final user = settingsCubit(api);
    addTearDown(user.close);
    await user.load();
    final pending = Completer<dynamic>();
    api.readResult = pending;
    final old = user.load();
    await user.update(SettingsUpdate({'show_in_travel_buddy': true}));
    pending.complete({'data': settingsUser(visible: false)});
    await old;
    expect(user.state.profile!.showInTravelBuddy, true);
  });

  test(
    'logout/account switch ignores old settings and resets shared user state',
    () async {
      final api = SettingsApi();
      final user = settingsCubit(api);
      addTearDown(user.close);
      await user.load();
      final pending = Completer<dynamic>();
      api.patchResult = pending;
      final old = user.update(SettingsUpdate({'locale': 'ar'}));
      api.user = settingsUser(id: 9);
      await preferences.saveToken('new-session');
      await Future<void>.delayed(Duration.zero);
      pending.complete({
        'data': {...settingsUser(), 'locale': 'ar'},
      });
      await old;
      expect(user.state.profile!.id, '9');
      expect(preferences.language.value, 'en');
      await preferences.clear();
      expect(user.state.profile, isNull);
      expect(preferences.currency.value, isNull);
    },
  );

  test(
    'different account response and disposed requests cannot overwrite current user',
    () async {
      final api = SettingsApi();
      final user = settingsCubit(api);
      await user.load();
      api.patchResult = {'data': settingsUser(id: 9)};
      await user.update(SettingsUpdate({'show_active_status': false}));
      expect(user.state.profile!.id, '7');
      expect(user.state.error, isNotNull);
      final pending = Completer<dynamic>();
      api.patchResult = pending;
      final old = user.update(SettingsUpdate({'locale': 'ar'}));
      await user.close();
      pending.complete({
        'data': {...settingsUser(), 'locale': 'ar'},
      });
      await old;
      expect(preferences.language.value, 'en');
    },
  );

  test(
    'confirmed visibility updates and refreshes Buddies, overriding stale home metadata',
    () async {
      final api = SettingsApi();
      final user = settingsCubit(api);
      addTearDown(user.close);
      await user.load();
      final homeApi = buddies.FakeApi(buddies.home(visible: false));
      final discovery = BuddiesCubit(
        repo: BuddiesRepo(apiService: homeApi),
        currentUser: user,
      );
      addTearDown(discovery.close);
      await discovery.load();
      expect(discovery.state.home!.meta.showInTravelBuddy, false);
      await user.update(SettingsUpdate({'show_in_travel_buddy': true}));
      await Future<void>.delayed(Duration.zero);
      expect(homeApi.calls, 2);
      expect(discovery.state.home!.meta.showInTravelBuddy, true);
    },
  );

  test(
    'own ProfileCubit receives confirmed current-user settings and clears on logout',
    () async {
      final api = SettingsApi();
      final user = settingsCubit(api);
      addTearDown(user.close);
      await user.load();
      final owner = ProfileCubit(
        profileRepo: ProfileRepo(apiService: api),
        currentUser: user,
      );
      addTearDown(owner.close);
      await owner.loadProfile();
      await user.update(SettingsUpdate({'show_active_status': false}));
      await Future<void>.delayed(Duration.zero);
      expect((owner.state as ProfileLoaded).profile.showActiveStatus, false);
      await preferences.clear();
      await Future<void>.delayed(Duration.zero);
      expect(owner.state, isA<ProfileInitial>());
    },
  );

  test(
    'settings responses cannot overwrite newer unrelated profile fields',
    () async {
      final api = SettingsApi();
      final user = settingsCubit(api);
      addTearDown(user.close);
      await user.load();
      api.user = {
        ...settingsUser(),
        'name': 'Newer profile edit',
        'posts_count': 12,
      };
      final owner = ProfileCubit(
        profileRepo: ProfileRepo(apiService: api),
        currentUser: user,
      );
      addTearDown(owner.close);
      await owner.loadProfile();
      api.patchResult = {
        'data': {
          ...settingsUser(),
          'name': 'Older response name',
          'show_active_status': false,
        },
      };
      await user.update(SettingsUpdate({'show_active_status': false}));
      await Future<void>.delayed(Duration.zero);
      final profile = (owner.state as ProfileLoaded).profile;
      expect(profile.name, 'Newer profile edit');
      expect(profile.postsCount, 12);
      expect(profile.showActiveStatus, false);
    },
  );

  testWidgets(
    'Settings toggles send a partial PATCH and preserve server state across navigation',
    (tester) async {
      final api = SettingsApi();
      final user = settingsCubit(api);
      addTearDown(user.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SettingsScreen(currentUser: user),
                  ),
                ),
                child: const Text('Open settings'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      final active = find.byType(Switch).first;
      expect(tester.widget<Switch>(active).value, true);
      await tester.tap(active);
      await tester.pumpAndSettle();
      expect(api.patches.single, {'show_active_status': false});
      Navigator.of(tester.element(find.text('Settings and Privacy'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch).first).value, false);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'saving indicator belongs to the affected control and errors do not reset toggles',
    (tester) async {
      final api = SettingsApi();
      final user = settingsCubit(api);
      addTearDown(user.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: SettingsScreen(currentUser: user),
        ),
      );
      await tester.pumpAndSettle();
      final pending = Completer<dynamic>();
      api.patchResult = pending;
      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester
            .widgetList<Switch>(find.byType(Switch))
            .every((control) => control.onChanged == null),
        true,
      );
      pending.completeError(ApiError(message: 'Offline'));
      await tester.pumpAndSettle();
      expect(find.text('Offline'), findsWidgets);
      expect(tester.widget<Switch>(find.byType(Switch).first).value, true);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'an in-flight settings update survives closing the screen in the same session',
    (tester) async {
      final api = SettingsApi();
      final user = settingsCubit(api);
      addTearDown(user.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => SettingsScreen(currentUser: user),
                  ),
                ),
                child: const Text('Open settings'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      final pending = Completer<dynamic>();
      api.patchResult = pending;
      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      Navigator.of(tester.element(find.text('Settings and Privacy'))).pop();
      await tester.pumpAndSettle();
      expect(user.isClosed, false);
      pending.complete({
        'data': {...settingsUser(), 'show_active_status': false},
      });
      await tester.pumpAndSettle();
      expect(user.state.profile!.showActiveStatus, false);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'confirmed logout clears session and removes authenticated Back navigation',
    (tester) async {
      final api = SettingsApi();
      final user = settingsCubit(api);
      addTearDown(user.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: SettingsScreen(
            currentUser: user,
            authRepo: AuthRepo(apiService: api),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Log Out'));
      await tester.tap(find.widgetWithText(TextButton, 'Log Out'));
      await tester.pumpAndSettle();
      expect(preferences.hasSession, false);
      expect(user.state.profile, isNull);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
        Navigator.of(tester.element(find.byType(LoginScreen))).canPop(),
        false,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'language applies server-backed preferences; Currency row is hidden by flag',
    (tester) async {
      final api = SettingsApi();
      final user = settingsCubit(api);
      addTearDown(user.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: SettingsScreen(currentUser: user),
        ),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Language'));
      expect(find.byType(LanguageBottomSheet), findsOneWidget);
      await tester.tap(find.text('العربية').last);
      await tester.pumpAndSettle();
      // Existing sheet may require its explicit Apply action.
      if (find.byType(LanguageBottomSheet).evaluate().isNotEmpty) {
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();
      }
      expect(preferences.language.value, 'ar');
      expect(api.patches.last, {'locale': 'ar'});
      // Currency returns with the Explore tab (kShowCurrencySetting).
      expect(kShowCurrencySetting, isFalse);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Currency'), findsNothing);
      expect(find.text('AED'), findsNothing);
      await tester.scrollUntilVisible(find.text('Log Out'), 160);
      expect(find.text('Currency'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Buddies invitation disappears after a confirmed settings mutation',
    (tester) async {
      final api = SettingsApi();
      final user = settingsCubit(api);
      addTearDown(user.close);
      await user.load();
      final homeApi = buddies.FakeApi(buddies.home(visible: false));
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: BlocProvider.value(
            value: user,
            child: BuddiesScreen(repo: BuddiesRepo(apiService: homeApi)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BuddiesVisibilityInvitation), findsOneWidget);
      await user.update(SettingsUpdate({'show_in_travel_buddy': true}));
      await tester.pumpAndSettle();
      expect(find.byType(BuddiesVisibilityInvitation), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'successful locale change reaches the real MaterialApp locale and RTL',
    (tester) async {
      final api = SettingsApi();
      final user = settingsCubit(api);
      await user.load();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('Locale probe')),
          ),
        ],
      );
      // Fake Messaging: real Firebase must never start in widget tests.
      final push = PushNotificationService(
        client: FakeMessagingClient()..available = false,
      );
      await tester.pumpWidget(
        app.MyApp(currentUser: user, router: router, pushNotifications: push),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
        const Locale('en'),
      );
      await user.update(SettingsUpdate({'locale': 'ar'}));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
        const Locale('ar'),
      );
      expect(
        Directionality.of(tester.element(find.byType(Scaffold).first)),
        TextDirection.rtl,
      );
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      await user.close();
    },
  );

  testWidgets('Settings controls fit a narrow viewport with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final user = settingsCubit(SettingsApi());
    addTearDown(user.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: SettingsScreen(currentUser: user),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Delete Account'), 160);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  group('Settings polish', () {
    Future<void> pumpCurrency(WidgetTester tester, {String? selected}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: CurrencyScreen(
            selectedCurrencyCode: selected,
            allowedCodes: SettingsRepo().supportedCurrencies,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> search(WidgetTester tester, String query) async {
      await tester.enterText(
        find.byKey(const ValueKey('currency-search')),
        query,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('default repo offers every backend currency', (tester) async {
      expect(SettingsRepo().supportedCurrencies, backendCurrencyCodes);
      expect(backendCurrencyCodes, hasLength(59));
      expect(backendCurrencyCodes, containsAll(['AED', 'USD', 'EGP', 'EUR']));
      await pumpCurrency(tester);
      expect(find.text('None'), findsOneWidget);
      expect(find.text('AED'), findsOneWidget);
      expect(find.text('ARS'), findsOneWidget);
    });

    testWidgets('search matches code and name, case-insensitively', (
      tester,
    ) async {
      Finder listed(String text) =>
          find.descendant(of: find.byType(ListView), matching: find.text(text));
      await pumpCurrency(tester, selected: 'AED');
      await search(tester, 'usd');
      expect(listed('USD'), findsOneWidget);
      expect(listed('AED'), findsNothing);
      // "None" only leads the unfiltered list.
      expect(find.byKey(const ValueKey('currency-none')), findsNothing);

      await search(tester, 'EGP');
      expect(listed('EGP'), findsOneWidget);
      expect(listed('Egypt Pound'), findsOneWidget);

      await search(tester, 'dollar');
      expect(listed('USD'), findsOneWidget);
      expect(listed('AUD'), findsOneWidget);
      expect(listed('CAD'), findsOneWidget);
      expect(listed('EGP'), findsNothing);

      await search(tester, 'zzzz');
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );

      await search(tester, '');
      expect(find.byKey(const ValueKey('currency-none')), findsOneWidget);
    });

    testWidgets('search field: search-normal icon, white cursor, no orange '
        'button', (tester) async {
      await pumpCurrency(tester);
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('currency-search')),
      );
      expect(field.cursorColor, Colors.white);
      final icon = tester.widget<SvgPicture>(
        find.descendant(
          of: find.byKey(const ValueKey('currency-search')),
          matching: find.byType(SvgPicture),
        ),
      );
      expect(
        (icon.bytesLoader as SvgAssetLoader).assetName,
        'assets/images/interactions/search-normal.svg',
      );
      expect(find.text('No preferred currency'), findsNothing);
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('Language value sits beside the chevron', (tester) async {
      final api = SettingsApi();
      final user = settingsCubit(api);
      addTearDown(user.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: SettingsScreen(currentUser: user),
        ),
      );
      await tester.pumpAndSettle();
      for (final (title, value) in [('Language', 'English')]) {
        final row = find.ancestor(
          of: find.text(title),
          matching: find.byType(InkWell),
        );
        final chevron = find.descendant(
          of: row.first,
          matching: find.byIcon(Icons.chevron_right_rounded),
        );
        final valueRect = tester.getRect(
          find.descendant(of: row.first, matching: find.text(value)),
        );
        expect(
          tester.getRect(chevron).left - valueRect.right,
          inInclusiveRange(0, 8),
        );
        expect(
          valueRect.left,
          greaterThan(tester.getRect(find.text(title)).right),
        );
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Settings back button is 44x44', (tester) async {
      final api = SettingsApi();
      final user = settingsCubit(api);
      addTearDown(user.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: SettingsScreen(currentUser: user),
        ),
      );
      await tester.pumpAndSettle();
      final glass = find.descendant(
        of: find.byType(BackButtonWidget),
        matching: find.byType(GlassSurface),
      );
      expect(tester.getSize(glass), const Size(44, 44));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('language sheet matches the post options sheet', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => LanguageBottomSheet.show(context, 'en'),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
      expect(
        sheet.shape,
        const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      );
      expect(sheet.backgroundColor, const Color(0xFF0A0A0A));
      expect(find.byType(SheetHandle), findsOneWidget);
    });
  });

  group('push permission hint under Push Notifications', () {
    Future<(PushNotificationService, FakeMessagingClient)> pumpSettings(
      WidgetTester tester, {
      required PushPermission status,
      bool available = true,
    }) async {
      final client = FakeMessagingClient()
        ..status = status
        ..available = available;
      final push = PushNotificationService(client: client);
      addTearDown(() async {
        push.dispose();
        await client.close();
      });
      await push.start();
      tester.view.physicalSize = const Size(390, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final user = settingsCubit(SettingsApi());
      addTearDown(user.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: SettingsScreen(currentUser: user, push: push),
        ),
      );
      await tester.pumpAndSettle();
      return (push, client);
    }

    testWidgets('blocked permission shows a muted hint with an orange Check', (
      tester,
    ) async {
      final (_, client) = await pumpSettings(
        tester,
        status: PushPermission.denied,
      );
      final hint = find.byKey(const ValueKey('push-permission-hint'));
      expect(hint, findsOneWidget);
      // Sits inside the Push Notifications row, under its subtitle.
      expect(
        tester.getTopLeft(hint).dy,
        greaterThanOrEqualTo(
          tester
              .getBottomLeft(find.text('Receive notifications on your phone'))
              .dy,
        ),
      );
      final message = tester.widget<Text>(
        find.textContaining('blocked on this device'),
      );
      expect(message.style!.fontSize, AppSizes.sp12);
      expect(message.style!.color, Colors.white54);
      final action = find.byKey(const ValueKey('push-permission-action'));
      expect(
        find.descendant(of: action, matching: find.text('Check')),
        findsOneWidget,
      );
      expect(
        tester.widget<TextButton>(action).style!.foregroundColor!.resolve({}),
        DarkColors.primaryColor,
      );
      // Still blocked: Check re-reads permission without prompting.
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(client.prompts, 0);
      expect(hint, findsOneWidget);
      // Allowed in device Settings, then Check: the hint goes away.
      client.status = PushPermission.authorized;
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(hint, findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('undecided permission offers Enable, which prompts', (
      tester,
    ) async {
      final (_, client) = await pumpSettings(
        tester,
        status: PushPermission.notDetermined,
      );
      expect(find.textContaining('aren’t allowed'), findsOneWidget);
      client.status = PushPermission.authorized;
      await tester.tap(find.text('Enable'));
      await tester.pumpAndSettle();
      expect(client.prompts, 1);
      expect(find.byKey(const ValueKey('push-permission-hint')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    for (final (label, status, available) in [
      ('allowed', PushPermission.authorized, true),
      ('unsupported device', PushPermission.denied, false),
    ]) {
      testWidgets('no hint when $label', (tester) async {
        await pumpSettings(tester, status: status, available: available);
        expect(
          find.byKey(const ValueKey('push-permission-hint')),
          findsNothing,
        );
        expect(find.text('Push Notifications'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      });
    }
  });
}
