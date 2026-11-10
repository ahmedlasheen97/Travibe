import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/places/city_places_provider.dart';
import 'package:travibe/core/places/photon_city_places_provider.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/buddies/data/buddies_repo.dart';
import 'package:travibe/features/buddies/screens/buddies_search_screen.dart';
import 'package:travibe/features/buddies/widgets/buddies_traveler_card.dart';
import '../../core/places/fake_city_places.dart';
import '../../core/places/photon_city_places_provider_test.dart' as photon;
import 'buddies_home_test.dart' as home;
import 'buddies_search_test.dart' as search;

class ReadOnlySearchApi extends home.FakeApi {
  ReadOnlySearchApi() : super(search.searchPage(ids: [1]));
  int mutations = 0;
  @override
  Future<dynamic> post(String endpoint, Map<String, dynamic> data) async {
    if (endpoint == 'buddies/search/recent') return super.post(endpoint, data);
    mutations++;
    throw StateError('Unexpected mutation');
  }

  @override
  Future<dynamic> patch(String endpoint, Map<String, dynamic> data) async {
    mutations++;
    throw StateError('Unexpected mutation');
  }

  @override
  Future<dynamic> put(String endpoint, Map<String, dynamic> data) async {
    mutations++;
    throw StateError('Unexpected mutation');
  }
}

void main() {
  final preferences = PreferencesManager();
  setUp(() async {
    ScreenUtil.configure(
      data: const MediaQueryData(size: Size(390, 844)),
      designSize: const Size(390, 844),
      minTextAdapt: false,
      splitScreenMode: false,
    );
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.saveToken('autocomplete-test');
  });
  tearDown(() => preferences.clear());

  Future<void> show(
    WidgetTester tester,
    home.FakeApi api,
    CityPlacesProvider? provider,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        home: BuddiesSearchScreen(
          repo: BuddiesRepo(apiService: api),
          placesProvider: provider,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), 'Lon');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Photon city selection sends only Laravel city and country fields',
    (tester) async {
      final api = ReadOnlySearchApi();
      final adapter = photon.PhotonAdapter();
      final provider = PhotonCityPlacesProvider(
        transport: Dio()..httpClientAdapter = adapter,
      );
      await preferences.setString('current_city', 'Cairo');
      await show(tester, api, provider);
      await tester.enterText(find.byType(TextField), 'Dub');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(api.calls, 0);
      expect(adapter.requests.single.queryParameters['osm_tag'], 'place:city');
      await tester.tap(find.text('Dubai, United Arab Emirates'));
      await tester.pumpAndSettle();
      expect(api.query, {
        'city': 'Dubai',
        'country_code': 'AE',
        'page': 1,
        'per_page': 15,
      });
      expect(api.calls, 1);
      expect(adapter.requests, hasLength(1));
      expect(api.mutations, 0);
      expect(preferences.getString('current_city'), 'Cairo');
      expect(find.text('Traveler 1'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(api.calls, 1);
      expect(find.byType(BuddiesTravelerCard), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'duplicate city names show countries; only resolved selection searches without profile writes',
    (tester) async {
      final api = ReadOnlySearchApi();
      await preferences.setString('current_city', 'Cairo');
      final provider = FakeCityPlaces()
        ..onAutocomplete = (_) async => [
          const CitySuggestion(
            id: 'london-gb',
            label: 'London, United Kingdom',
          ),
          const CitySuggestion(
            id: 'london-ca',
            label: 'London, Ontario, Canada',
          ),
        ];
      provider.onResolve = (s) async => CitySelection(
        cityName: 'London',
        countryName: 'Canada',
        countryCode: 'CA',
        latitude: 0,
        longitude: 0,
      );
      await show(tester, api, provider);
      await type(tester);
      expect(find.text('London, United Kingdom'), findsOneWidget);
      expect(find.text('London, Ontario, Canada'), findsOneWidget);
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
      expect(api.calls, 0);
      final details = Completer<CitySelection>();
      provider.onResolve = (s) => details.future;
      await tester.tap(find.text('London, Ontario, Canada'));
      await tester.pump();
      expect(find.text('Confirming city…'), findsOneWidget);
      expect(api.calls, 0);
      details.complete(
        CitySelection(
          cityName: 'London',
          countryName: 'Canada',
          countryCode: 'CA',
          latitude: 0,
          longitude: 0,
        ),
      );
      await tester.pumpAndSettle();
      expect(api.query, {
        'city': 'London',
        'country_code': 'CA',
        'page': 1,
        'per_page': 15,
      });
      expect(find.text('Traveler 1'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'London, Canada',
      );
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        false,
      );
      expect(api.mutations, 0);
      expect(preferences.getString('current_city'), 'Cairo');
      expect(api.path, 'buddies/search');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'empty and failed autocomplete retry never trigger an incomplete people request',
    (tester) async {
      final api = home.FakeApi(search.searchPage());
      final provider = FakeCityPlaces()..onAutocomplete = (_) async => [];
      await show(tester, api, provider);
      await type(tester);
      expect(find.text('No cities found. Try another name.'), findsOneWidget);
      expect(api.calls, 0);
      provider.onAutocomplete = (_) async =>
          throw const CityPlacesException('Places offline');
      await tester.enterText(find.byType(TextField), 'Lond');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('Places offline'), findsOneWidget);
      provider.onAutocomplete = null;
      await tester.tap(find.text('Retry cities'));
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsOneWidget);
      expect(api.calls, 0);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(api.calls, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'clear cancels an in-flight city resolution and keeps backend idle',
    (tester) async {
      final api = home.FakeApi(search.searchPage());
      final provider = FakeCityPlaces();
      final details = Completer<CitySelection>();
      provider.onResolve = (_) => details.future;
      await show(tester, api, provider);
      await type(tester);
      await tester.tap(find.byType(ListTile));
      await tester.pump();
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      details.complete(
        CitySelection(
          cityName: 'London',
          countryName: 'Canada',
          countryCode: 'CA',
          latitude: 0,
          longitude: 0,
        ),
      );
      await tester.pumpAndSettle();
      expect(api.calls, 0);
      expect(find.byType(BuddiesTravelerCard), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('provider errors have no hardcoded fallback cities', (
    tester,
  ) async {
    final api = home.FakeApi(search.searchPage());
    final provider = FakeCityPlaces()
      ..onAutocomplete = (_) async =>
          throw const CityPlacesException('Photon unavailable');
    await show(tester, api, provider);
    await type(tester);
    expect(find.text('Photon unavailable'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
    expect(api.calls, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Back abandons pending autocomplete without returning or mutating people results',
    (tester) async {
      final api = home.FakeApi(search.searchPage());
      final provider = FakeCityPlaces();
      final pending = Completer<List<CitySuggestion>>();
      provider.onAutocomplete = (_) => pending.future;
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => BuddiesSearchScreen(
                      repo: BuddiesRepo(apiService: api),
                      placesProvider: provider,
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Lon');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.byTooltip('Back'));
      await tester.pump(const Duration(seconds: 1));
      pending.complete([
        const CitySuggestion(id: 'Lon', label: 'London, Canada'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(api.calls, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
