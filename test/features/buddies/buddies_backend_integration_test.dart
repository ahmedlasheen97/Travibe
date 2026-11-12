import 'package:travibe/core/datasource/remotedata/dio_client.dart';
import 'package:travibe/root.dart';
import 'package:travibe/features/buddies/widgets/buddies_traveler_skeleton.dart';
import 'package:travibe/features/buddies/screens/buddies_filters_screen.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import '../home/home_experience_fixtures.dart' as feeds;
import 'buddies_filters_test.dart' as filters;
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/core/location/device_location_service.dart';
import 'package:travibe/core/places/city_places_provider.dart';
import 'package:travibe/core/places/photon_city_places_provider.dart';
import 'package:travibe/core/reference/countries_repo.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/buddies/cubit/allow_location_cubit.dart';
import 'package:travibe/features/buddies/cubit/buddies_cubit.dart';
import 'package:travibe/features/buddies/cubit/buddies_search_cubit.dart';
import 'package:travibe/features/buddies/data/buddies_repo.dart';
import 'package:travibe/features/buddies/data/buddies_filters.dart';
import 'package:travibe/features/buddies/screens/buddies_screen.dart';
import 'package:travibe/features/buddies/widgets/buddies_traveler_card.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/cubit/profile_cubit.dart';
import 'package:travibe/features/profile/data/profile_repo.dart';
import 'package:travibe/features/profile/data/settings_repo.dart';
import 'package:travibe/features/profilesetup/cubit/profile_setup_cubit.dart';
import 'package:travibe/features/profilesetup/data/profile_setup_repo.dart';
import 'buddies_home_test.dart' as home;
import 'buddies_search_test.dart' as search;
import '../../core/places/photon_city_places_provider_test.dart' as photon;

CitySelection cairo() => CitySelection(
  cityName: 'Cairo',
  countryName: 'Egypt',
  countryCode: 'eg',
  latitude: 30.04,
  longitude: 31.23,
);

class LocationApi extends ApiService {
  final calls = <String>[];
  final payloads = <Map<String, dynamic>>[];
  final profile = <String, dynamic>{
    'id': 7,
    'name': 'Account',
    'locale': 'en',
    'currency_code': 'AED',
    'show_active_status': true,
    'show_in_travel_buddy': false,
    'push_notifications_enabled': true,
    'current_location': null,
  };
  ApiError? putError, settingsError;
  Completer<dynamic>? pendingPut;
  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
    calls.add('GET $endpoint');
    return {'data': Map.of(profile)};
  }

  @override
  Future<dynamic> put(String endpoint, Map<String, dynamic> data) async {
    calls.add('PUT $endpoint');
    payloads.add(data);
    if (pendingPut != null) return pendingPut!.future;
    if (putError != null) throw putError!;
    profile['current_location'] = data['location'];
    return {'data': Map.of(profile)};
  }

  @override
  Future<dynamic> delete(String endpoint) async {
    calls.add('DELETE $endpoint');
    profile['current_location'] = null;
    return null; // actual 204 has no JSON resource
  }

  @override
  Future<dynamic> patch(String endpoint, Map<String, dynamic> data) async {
    calls.add('PATCH $endpoint');
    payloads.add(data);
    if (settingsError != null) throw settingsError!;
    profile.addAll(data);
    return {'data': Map.of(profile)};
  }

  @override
  Future<dynamic> post(String endpoint, Map<String, dynamic> data) async => {};
}

class Device implements DeviceLocationService {
  Device(this.events);
  final List<String> events;
  Object? failure;
  @override
  Future<DeviceCoordinates> locate() async {
    events.add('device');
    if (failure != null) throw failure!;
    return const DeviceCoordinates(30.04, 31.23);
  }

  @override
  Future<void> openSettings() async {}
}

class Reverse implements CityReverseGeocoder {
  Reverse(this.events);
  final List<String> events;
  Object? failure;
  @override
  Future<CitySelection> reverse(double latitude, double longitude) async {
    events.add('reverse');
    if (failure != null) throw failure!;
    expect(latitude, 30.04);
    expect(longitude, 31.23);
    return cairo();
  }
}

void main() {
  final preferences = PreferencesManager();
  late LocationApi api;
  late CurrentUserCubit user;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.saveToken('test-only');
    ScreenUtil.configure(
      data: const MediaQueryData(size: Size(390, 844)),
      designSize: const Size(390, 844),
      minTextAdapt: false,
      splitScreenMode: false,
    );
    api = LocationApi();
    user = CurrentUserCubit(
      profileRepo: ProfileRepo(apiService: api),
      settingsRepo: SettingsRepo(apiService: api),
    );
    await user.load();
    api.calls.clear();
  });
  tearDown(() async {
    await user.close();
    await preferences.clear();
  });

  test(
    'location PUT sends exactly City, CODE and canonical resource reloads',
    () async {
      expect(await user.saveLocation(cairo()), true);
      expect(api.calls, ['PUT profile/location']);
      expect(api.payloads.single, {'location': 'Cairo, EG'});
      expect(user.state.profile!.currentLocation, 'Cairo, EG');
      expect(user.state.profile!.showInTravelBuddy, false);
      await user.load();
      expect(user.state.profile!.currentLocation, 'Cairo, EG');
    },
  );
  test(
    'DELETE 204 clears canonical location without changing visibility',
    () async {
      await user.saveLocation(cairo());
      await user.clearLocation();
      expect(api.calls.last, 'DELETE profile/location');
      expect(user.state.profile!.currentLocation, isNull);
      expect(user.state.profile!.showInTravelBuddy, false);
    },
  );
  for (final status in [401, 403, 422, 429, 500]) {
    test('location $status is handled without changing user data', () async {
      api.putError = ApiError(message: 'Location rejected', statusCode: status);
      expect(await user.saveLocation(cairo()), false);
      expect(user.state.error!.statusCode, status);
      expect(user.state.profile!.currentLocation, isNull);
      expect(user.state.saving, isNull);
    });
  }
  test('location responses cannot cross an account change', () async {
    api.pendingPut = Completer<dynamic>();
    final pending = user.saveLocation(cairo());
    await preferences.saveToken('different-account');
    api.pendingPut!.complete({
      'data': {...api.profile, 'current_location': 'Cairo, EG'},
    });
    expect(await pending, false);
    await Future<void>.delayed(Duration.zero);
    expect(user.state.profile?.currentLocation, isNull);
  });
  test('location save coalesces repeated submissions', () async {
    api.pendingPut = Completer<dynamic>();
    final pending = user.saveLocation(cairo());
    expect(await user.saveLocation(cairo()), false);
    expect(api.calls, ['PUT profile/location']);
    api.pendingPut!.complete({
      'data': {...api.profile, 'current_location': 'Cairo, EG'},
    });
    await pending;
  });
  test(
    'own ProfileCubit receives location updates and deletion immediately',
    () async {
      final profile = ProfileCubit(
        profileRepo: ProfileRepo(apiService: api),
        currentUser: user,
      );
      await profile.loadProfile();
      await user.saveLocation(cairo());
      await Future<void>.delayed(Duration.zero);
      expect(
        (profile.state as ProfileLoaded).profile.currentLocation,
        'Cairo, EG',
      );
      await user.clearLocation();
      await Future<void>.delayed(Duration.zero);
      expect((profile.state as ProfileLoaded).profile.currentLocation, isNull);
      await profile.close();
    },
  );
  test(
    'Profile Setup city selection uses location PUT without visibility PATCH',
    () async {
      final setup = ProfileSetupCubit(
        repo: ProfileSetupRepo(apiService: api),
        currentUser: user,
      );
      await setup.setCity(cairo());
      await setup.saveBasicInfo();
      expect(api.calls.first, 'PUT profile/location');
      expect(api.calls, isNot(contains('PATCH settings')));
      expect(setup.state.currentLocation, 'Cairo, EG');
      await setup.close();
    },
  );
  test(
    'Allow Location orders device, reverse, PUT then settings PATCH',
    () async {
      final flow = AllowLocationCubit(
        currentUser: user,
        device: Device(api.calls),
        geocoder: Reverse(api.calls),
      );
      await flow.allow();
      expect(api.calls, [
        'device',
        'reverse',
        'PUT profile/location',
        'PATCH settings',
      ]);
      expect(api.payloads, [
        {'location': 'Cairo, EG'},
        {'show_in_travel_buddy': true},
      ]);
      expect(flow.state.enabled, true);
      expect(flow.state.busy, false);
      await flow.close();
    },
  );
  for (final message in [
    'Permission denied',
    'Permanently denied',
    'Services disabled',
    'Device timeout',
  ]) {
    test('$message does not save location or enable visibility', () async {
      final device = Device(api.calls)
        ..failure = DeviceLocationException(message);
      final flow = AllowLocationCubit(
        currentUser: user,
        device: device,
        geocoder: Reverse(api.calls),
      );
      await flow.allow();
      expect(api.calls, ['device']);
      expect(flow.state.error, message);
      expect(flow.state.busy, false);
      expect(user.state.profile!.showInTravelBuddy, false);
      await flow.close();
    });
  }
  test('reverse failure never enables visibility', () async {
    final reverse = Reverse(api.calls)
      ..failure = const CityPlacesException('No usable city');
    final flow = AllowLocationCubit(
      currentUser: user,
      device: Device(api.calls),
      geocoder: reverse,
    );
    await flow.allow();
    expect(api.calls, ['device', 'reverse']);
    expect(flow.state.error, 'No usable city');
    await flow.close();
  });
  test('location save failure never enables visibility', () async {
    api.putError = ApiError(message: 'Invalid location', statusCode: 422);
    final flow = AllowLocationCubit(
      currentUser: user,
      device: Device(api.calls),
      geocoder: Reverse(api.calls),
    );
    await flow.allow();
    expect(api.calls, ['device', 'reverse', 'PUT profile/location']);
    expect(flow.state.locationSaved, false);
    await flow.close();
  });
  test(
    'partial failure retains location; retry only enables visibility',
    () async {
      api.settingsError = ApiError(message: 'Offline');
      final flow = AllowLocationCubit(
        currentUser: user,
        device: Device(api.calls),
        geocoder: Reverse(api.calls),
      );
      await flow.allow();
      expect(flow.state.locationSaved, true);
      expect(flow.state.enabled, false);
      expect(user.state.profile!.currentLocation, 'Cairo, EG');
      api.calls.clear();
      api.settingsError = null;
      await flow.allow();
      expect(api.calls, ['PATCH settings']);
      expect(flow.state.enabled, true);
      await flow.close();
    },
  );
  test('repeated Allow Location taps do not duplicate requests', () async {
    api.pendingPut = Completer<dynamic>();
    final flow = AllowLocationCubit(
      currentUser: user,
      device: Device(api.calls),
      geocoder: Reverse(api.calls),
    );
    final pending = flow.allow();
    await Future<void>.delayed(Duration.zero);
    await flow.allow();
    expect(api.calls, ['device', 'reverse', 'PUT profile/location']);
    api.pendingPut!.complete({
      'data': {...api.profile, 'current_location': 'Cairo, EG'},
    });
    await pending;
    await flow.close();
  });
  test(
    'Allow Location stops after session changes during the location write',
    () async {
      api.pendingPut = Completer<dynamic>();
      final flow = AllowLocationCubit(
        currentUser: user,
        device: Device(api.calls),
        geocoder: Reverse(api.calls),
      );
      final pending = flow.allow();
      await Future<void>.delayed(Duration.zero);
      await preferences.saveToken('another-account');
      api.pendingPut!.complete({
        'data': {...api.profile, 'current_location': 'Cairo, EG'},
      });
      await pending;
      expect(api.calls, isNot(contains('PATCH settings')));
      expect(flow.state.enabled, false);
      await flow.close();
    },
  );
  test(
    'location changes refresh Buddies independently of visibility',
    () async {
      final backend = home.FakeApi(home.home());
      final buddies = BuddiesCubit(
        repo: BuddiesRepo(apiService: backend),
        currentUser: user,
      );
      await buddies.load();
      final count = backend.calls;
      await user.saveLocation(cairo());
      await Future<void>.delayed(Duration.zero);
      expect(backend.calls, greaterThan(count));
      await buddies.close();
    },
  );
  test(
    'recent destination saves once per selection; typing, filters and pagination do not POST',
    () async {
      final backend = home.FakeApi(
        search.searchPage(ids: [1], next: '?page=2'),
      );
      final cubit = BuddiesSearchCubit(repo: BuddiesRepo(apiService: backend));
      cubit.setCity('Ca');
      expect(backend.calls, 0);
      expect(backend.recent, isEmpty);
      final city = cairo();
      cubit.selectCity(city);
      cubit.selectCity(city);
      await Future<void>.delayed(Duration.zero);
      expect(backend.recent, [
        {'destination': 'Cairo, Egypt'},
      ]);
      expect(backend.query, {
        'city': 'Cairo',
        'country_code': 'EG',
        'page': 1,
        'per_page': 15,
      });
      backend.result = search.searchPage(ids: [1, 2], number: 2);
      await cubit.loadMore();
      expect(Uri.parse(backend.path!).queryParameters['page'], '2');
      expect(cubit.state.items.map((e) => e.id), [1, 2]);
      cubit.apply(BuddiesFilters(gender: ['female']));
      await Future<void>.delayed(Duration.zero);
      expect(backend.query!['page'], 1);
      expect(cubit.state.selectedCity, city);
      expect(backend.recent, hasLength(1));
      expect(user.state.profile!.currentLocation, isNull);
      await cubit.close();
    },
  );
  test(
    'failed recent save does not block empty or successful people results',
    () async {
      final backend = FailingRecentApi();
      final cubit = BuddiesSearchCubit(repo: BuddiesRepo(apiService: backend));
      cubit.selectCity(cairo());
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.page, isNotNull);
      expect(cubit.state.error, isNull);
      expect(cubit.state.recentError, isNotNull);
      await cubit.close();
    },
  );
  test('Photon reverse uses coordinates, city layer and honest UA', () async {
    final adapter = photon.PhotonAdapter()
      ..data = photon.photonCollection([
        photon.photonFeature(
          name: 'Cairo',
          country: 'Egypt',
          code: 'eg',
          lon: 31.23,
          lat: 30.04,
        ),
      ]);
    final provider = PhotonCityPlacesProvider(
      transport: Dio()..httpClientAdapter = adapter,
    );
    final city = await provider.reverse(30.04, 31.23);
    final request = adapter.requests.single;
    expect(request.uri.path, '/reverse');
    expect(request.queryParameters, {
      'lat': 30.04,
      'lon': 31.23,
      'limit': 6,
      'lang': 'en',
      'layer': 'city',
    });
    expect(request.headers['User-Agent'], PhotonCityPlacesProvider.userAgent);
    expect(request.headers.containsKey('Authorization'), false);
    expect(city.countryCode, 'EG');
    expect(city.latitude, 30.04);
    expect(city.longitude, 31.23);
  });
  test('reverse refuses unrelated and incomplete features', () async {
    final feature = photon.photonFeature();
    (feature['properties'] as Map)['type'] = 'street';
    final adapter = photon.PhotonAdapter()
      ..data = photon.photonCollection([feature]);
    await expectLater(
      PhotonCityPlacesProvider(
        transport: Dio()..httpClientAdapter = adapter,
      ).reverse(0, 0),
      throwsA(isA<CityPlacesException>()),
    );
  });
  for (final locale in ['en', 'ar']) {
    test('countries $locale is public, localized and cached', () async {
      final adapter = photon.PhotonAdapter()
        ..data = {
          'data': [
            {
              'code': 'EG',
              'name': locale == 'ar' ? 'مصر' : 'Egypt',
              'name_en': 'Egypt',
              'name_ar': 'مصر',
            },
          ],
        };
      final repo = CountriesRepo(transport: Dio()..httpClientAdapter = adapter);
      final countries = await repo.load(locale);
      await repo.load(locale);
      expect(countries.single.code, 'EG');
      expect(countries.single.name, locale == 'ar' ? 'مصر' : 'Egypt');
      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.headers['Accept-Language'], locale);
      expect(
        adapter.requests.single.headers.containsKey('Authorization'),
        false,
      );
      await repo.load(locale == 'ar' ? 'en' : 'ar');
      expect(adapter.requests, hasLength(2));
    });
  }
  test(
    'country malformed responses and HTTP errors remain retryable',
    () async {
      final adapter = photon.PhotonAdapter()
        ..data = {
          'data': [
            {'code': 'Egypt'},
          ],
        };
      final repo = CountriesRepo(transport: Dio()..httpClientAdapter = adapter);
      await expectLater(repo.load('en'), throwsA(isA<ApiError>()));
      adapter.status = 500;
      await expectLater(repo.load('en'), throwsA(isA<ApiError>()));
      adapter.status = 200;
      adapter.data = {'data': []};
      expect(await repo.load('en'), isEmpty);
    },
  );
  testWidgets(
    'one floating initial and retap loader, no layout shifts on refresh',
    (tester) async {
      final backend = home.FakeApi(Completer<dynamic>());
      final signal = ValueNotifier(0);
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: BuddiesScreen(
            repo: BuddiesRepo(apiService: backend),
            refreshSignal: signal,
          ),
        ),
      );
      await tester.pump();
      // First load: card skeletons, no floating loader.
      expect(find.byType(BuddiesSectionSkeleton), findsNWidgets(2));
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      (backend.result as Completer<dynamic>).complete(
        home.home(users: [home.buddy()]),
      );
      await tester.pumpAndSettle();
      final card = find.byType(BuddiesTravelerCard).first;
      final element = tester.element(card);
      final rect = tester.getRect(card);
      backend.result = Completer<dynamic>();
      signal.value++;
      signal.value++;
      await tester.pump();
      await tester.pump();
      expect(backend.calls, 2);
      // Refresh over existing cards keeps them and floats one loader.
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      final loader = tester.getRect(find.byType(CupertinoActivityIndicator));
      expect(loader.top, 0);
      expect(loader.center.dx, 400);
      expect(find.byType(BuddiesSectionSkeleton), findsNothing);
      expect(tester.element(card), same(element));
      expect(tester.getRect(card), rect);
      expect(find.byType(RefreshProgressIndicator), findsNothing);
      (backend.result as Completer<dynamic>).completeError(
        ApiError(message: 'Offline'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(tester.element(card), same(element));
      await tester.pumpWidget(const SizedBox());
      signal.dispose();
    },
  );
  testWidgets(
    'pull refresh shares a SafeArea overlay and preserves scroll and cards',
    (tester) async {
      tester.view.physicalSize = const Size(390, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.padding = const FakeViewPadding(top: 44);
      tester.view.viewPadding = const FakeViewPadding(top: 44);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      final backend = home.FakeApi(
        home.home(users: [for (var id = 1; id <= 8; id++) home.buddy(id: id)]),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: BuddiesScreen(repo: BuddiesRepo(apiService: backend)),
        ),
      );
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      scroll.position.jumpTo(scroll.position.maxScrollExtent / 2);
      await tester.pump();
      final offset = scroll.position.pixels;
      final element = tester.element(find.byType(BuddiesTravelerCard).first);
      backend.result = Completer<dynamic>();
      final refresh = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pump();
      await tester.pump();
      final spinner = find.byType(CupertinoActivityIndicator);
      expect(spinner, findsOneWidget);
      expect(tester.getTopLeft(spinner).dy, 44);
      expect(
        tester.widget<CupertinoActivityIndicator>(spinner).color,
        DarkColors.primaryColor,
      );
      expect(tester.widget<CupertinoActivityIndicator>(spinner).radius, 15);
      expect(
        tester.element(find.byType(BuddiesTravelerCard).first),
        same(element),
      );
      expect(scroll.position.pixels, offset);
      expect(find.byType(RefreshProgressIndicator), findsNothing);
      (backend.result as Completer<dynamic>).complete(
        home.home(users: [for (var id = 1; id <= 8; id++) home.buddy(id: id)]),
      );
      await refresh;
      await tester.pumpAndSettle();
      expect(spinner, findsNothing);
      expect(scroll.position.pixels, offset);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Buddies navbar retap refreshes once; returning to cached Buddies does not refresh',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final backend = home.FakeApi(home.home());
      final account = feeds.AccountRepo();
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            theme: darkTheme,
            home: Root(
              postsRepo: feeds.EmptyPostsRepo(),
              homeAccountRepo: account,
              followRepo: feeds.PeopleRepo(account),
              buddiesRepo: BuddiesRepo(apiService: backend),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester
          .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
          .onTap!(3);
      await tester.pumpAndSettle();
      expect(backend.calls, 1);
      backend.result = Completer<dynamic>();
      final nav = tester.widget<BottomNavigationBar>(
        find.byType(BottomNavigationBar),
      );
      nav.onTap!(3);
      nav.onTap!(3);
      await tester.pump();
      await tester.pump();
      expect(backend.calls, 2);
      // Refreshing an empty Buddies home shows skeletons, not a spinner.
      expect(find.byType(BuddiesSectionSkeleton), findsNWidgets(2));
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      (backend.result as Completer<dynamic>).complete(home.home());
      await tester.pumpAndSettle();
      tester
          .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
          .onTap!(0);
      await tester.pumpAndSettle();
      tester
          .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
          .onTap!(3);
      await tester.pumpAndSettle();
      expect(backend.calls, 2);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'country labels react to locale changes without changing selected codes',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: BuddiesFiltersScreen(
            initial: BuddiesFilters(nationality: ['EG']),
            catalogRepo: filters.FilterCatalog(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(InputChip, 'Egypt'), findsOneWidget);
      await preferences.saveLanguage('ar');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(InputChip, 'مصر'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'refresh retains cached search results and failed refresh retries page one',
    () async {
      final backend = home.FakeApi(
        search.searchPage(ids: [1], next: '?page=2'),
      );
      final cubit = BuddiesSearchCubit(repo: BuddiesRepo(apiService: backend));
      cubit.selectCity(cairo());
      await Future<void>.delayed(Duration.zero);
      backend.result = Completer<dynamic>();
      final refresh = cubit.refresh();
      expect(cubit.state.items.single.id, 1);
      expect(cubit.state.refreshing, true);
      (backend.result as Completer<dynamic>).completeError(
        ApiError(message: 'Offline'),
      );
      await refresh;
      expect(cubit.state.items.single.id, 1);
      expect(cubit.state.loading, false);
      expect(cubit.state.refreshing, true);
      backend.result = search.searchPage(ids: [2]);
      await cubit.refresh();
      expect(backend.query!['page'], 1);
      expect(cubit.state.items.single.id, 2);
      await cubit.close();
    },
  );
  test(
    'real Dio serialization sends only location and handles DELETE 204 without JSON',
    () async {
      final adapter = photon.PhotonAdapter()
        ..data = {
          'data': {...api.profile, 'current_location': 'Cairo, EG'},
        };
      final client = DioClient();
      client.dio.httpClientAdapter = adapter;
      final repo = ProfileRepo(apiService: ApiService(client: client));
      await repo.saveLocation(cairo());
      expect(adapter.requests.single.method, 'PUT');
      expect(adapter.requests.single.uri.path, '/api/v1/profile/location');
      expect(adapter.requests.single.data, {'location': 'Cairo, EG'});
      adapter.status = 204;
      adapter.data = null;
      await repo.clearLocation();
      expect(adapter.requests.last.method, 'DELETE');
      expect(adapter.requests.last.data, isNull);
    },
  );
  test(
    'search stops at last_page even if an inconsistent next link remains',
    () async {
      final json = search.searchPage(number: 3, next: '?page=4');
      final backend = home.FakeApi(json);
      final cubit = BuddiesSearchCubit(repo: BuddiesRepo(apiService: backend));
      cubit.selectCity(cairo());
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.page!.next, isNull);
      await cubit.loadMore();
      expect(backend.calls, 1);
      await cubit.close();
    },
  );
  test('logout clears the cached own-profile location immediately', () async {
    final owner = ProfileCubit(
      profileRepo: ProfileRepo(apiService: api),
      currentUser: user,
    );
    await owner.loadProfile();
    await user.saveLocation(cairo());
    await Future<void>.delayed(Duration.zero);
    expect((owner.state as ProfileLoaded).profile.currentLocation, 'Cairo, EG');
    await preferences.clear();
    expect(owner.state, isA<ProfileInitial>());
    await owner.close();
  });
  test(
    'account changes clear pending Profile Setup city and old identity',
    () async {
      final setup = ProfileSetupCubit(
        repo: ProfileSetupRepo(apiService: api),
        currentUser: user,
      );
      setup.fullNameController.text = 'Previous account';
      api.pendingPut = Completer<dynamic>();
      final save = setup.setCity(cairo());
      await preferences.saveToken('next-account');
      api.pendingPut!.complete({
        'data': {...api.profile, 'current_location': 'Cairo, EG'},
      });
      await save;
      expect(setup.state.currentLocation, isNull);
      expect(setup.fullNameController.text, isEmpty);
      expect(setup.state.isSaving, false);
      await setup.close();
    },
  );
}

class FailingRecentApi extends home.FakeApi {
  FailingRecentApi() : super(search.searchPage());
  @override
  Future<dynamic> post(String endpoint, Map<String, dynamic> data) async {
    throw ApiError(message: 'Recent unavailable');
  }
}
