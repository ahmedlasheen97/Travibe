import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:travibe/core/places/city_places_provider.dart';
import '../../core/places/fake_city_places.dart';
import 'dart:ui' show SemanticsAction;
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
import 'package:travibe/features/buddies/cubit/buddies_listing_cubit.dart';
import 'package:travibe/features/buddies/cubit/buddies_search_cubit.dart';
import 'package:travibe/features/buddies/data/buddies_filters.dart';
import 'package:travibe/features/buddies/data/buddies_repo.dart';
import 'package:travibe/features/buddies/data/buddies_search_query.dart';
import 'package:travibe/features/buddies/screens/buddies_screen.dart';
import 'package:travibe/features/buddies/screens/buddies_search_screen.dart';
import 'package:travibe/features/buddies/screens/buddies_filters_screen.dart';
import 'package:travibe/features/buddies/widgets/buddies_traveler_card.dart';
import 'buddies_home_test.dart' as home;
import 'buddies_listing_test.dart' as listing;
import 'buddies_filters_test.dart' as filters;

Map<String, dynamic> searchPage({
  List<int> ids = const [],
  int number = 1,
  String? next,
}) {
  final json = listing.page(ids: ids, number: number, next: next);
  (json['meta'] as Map)
    ..remove('has_current_city')
    ..remove('current_city');
  for (final item in json['data'] as List) {
    (item as Map).remove('trip');
  }
  return json;
}

Future<void> showSearch(
  WidgetTester tester,
  home.FakeApi api, {
  BlockCubit? blocks,
}) async {
  Widget screen = BuddiesSearchScreen(
    repo: BuddiesRepo(apiService: api),
    catalogRepo: filters.FilterCatalog(),
    placesProvider: FakeCityPlaces(),
  );
  if (blocks != null) {
    screen = BlocProvider<BlockCubit>.value(value: blocks, child: screen);
  }
  await tester.pumpWidget(MaterialApp(theme: darkTheme, home: screen));
  await tester.pumpAndSettle();
}

Future<void> searchText(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
  final suggestion = find.byType(ListTile);
  if (suggestion.evaluate().isNotEmpty) {
    await tester.tap(suggestion.first);
    await tester.pumpAndSettle();
  }
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
    await preferences.saveToken('search-test');
  });
  tearDown(() => preferences.clear());

  test(
    'serializes exact search parameters, country and multi-value filters',
    () async {
      final api = home.FakeApi(searchPage(ids: [1]));
      await BuddiesRepo(apiService: api).search(
        query: BuddiesSearchQuery(
          city: '  Bali, Indonesia  ',
          countryCode: 'ID',
          perPage: 100,
          filters: BuddiesFilters(
            gender: ['male', 'female'],
            nationality: ['EG', 'IT'],
            languages: ['language-a'],
            interests: ['interest-a'],
            travelStyles: ['style-a'],
          ),
        ),
      );
      expect(api.path, 'buddies/search');
      expect(api.query, {
        'city': 'Bali, Indonesia',
        'country_code': 'ID',
        'page': 1,
        'per_page': 100,
        'gender[]': ['male', 'female'],
        'nationality[]': ['EG', 'IT'],
        'languages[]': ['language-a'],
        'interests[]': ['interest-a'],
        'travel_styles[]': ['style-a'],
      });
      expect(BuddiesSearchQuery(city: 'B').toQuery(), {
        'city': 'B',
        'page': 1,
        'per_page': 15,
      });
    },
  );

  test(
    'validates required city, 120 unicode characters, country and per-page',
    () {
      for (final text in ['', '   ', 'a' * 121, '🌍' * 121]) {
        expect(() => BuddiesSearchQuery(city: text), throwsArgumentError);
      }
      expect(BuddiesSearchQuery(city: 'a' * 120).city.length, 120);
      expect(BuddiesSearchQuery(city: '🌍' * 120).city.runes.length, 120);
      expect(
        () => BuddiesSearchQuery(city: 'Cairo', countryCode: 'Egypt'),
        throwsArgumentError,
      );
      for (final perPage in [0, 101]) {
        expect(
          () => BuddiesSearchQuery(city: 'Cairo', perPage: perPage),
          throwsArgumentError,
        );
      }
    },
  );

  test(
    'absent trip and nullable interests/avatar/location parse safely; malformed responses fail visibly',
    () async {
      final json = searchPage(ids: [1]);
      (json['data'] as List).single['interests'] = null;
      final api = home.FakeApi(json);
      final repo = BuddiesRepo(apiService: api);
      final result = await repo.search(
        query: BuddiesSearchQuery(city: 'Cairo'),
      );
      expect(result.items.single.interests, isEmpty);
      expect(result.items.single.avatarUrl, isNull);
      expect(result.items.single.trip, isNull);
      expect(result.hasCurrentCity, isNull);
      api.result = {'data': []};
      await expectLater(
        repo.search(query: BuddiesSearchQuery(city: 'Cairo')),
        throwsA(isA<ApiError>()),
      );
    },
  );

  test(
    'continuation retains page number while preserving the whole applied search',
    () async {
      final api = home.FakeApi(searchPage(number: 2));
      final query = BuddiesSearchQuery(
        city: 'Bali',
        filters: BuddiesFilters(gender: ['female']),
      );
      await BuddiesRepo(apiService: api).search(
        query: query,
        next:
            '?page=2&cursor=obsolete&city=wrong&destination=wrong&sort=soonest&trip=1&starts_on=2026-11-01&ends_on=2026-11-10&destination_country_code=US&country_code=US&gender%5B0%5D=male&per_page=90',
      );
      final uri = Uri.parse(api.path!);
      expect(uri.path, '/api/v1/buddies/search');
      expect(uri.queryParametersAll, {
        'page': ['2'],
        'city': ['Bali'],
        'gender[]': ['female'],
        'per_page': ['15'],
      });
      expect(api.query, isNull);
      await BuddiesRepo(apiService: api).search(
        query: BuddiesSearchQuery(city: 'Cairo', countryCode: 'EG'),
        next: '?page=2',
      );
      expect(Uri.parse(api.path!).queryParameters['country_code'], 'EG');
    },
  );

  for (final next in [
    'https://evil.example/api/v1/buddies/search?page=2',
    'http://travibeapp.com/api/v1/buddies/search',
    'https://travibeapp.com/api/v1/buddies/in-your-city?page=2',
    '?page=2#fragment',
    'https://[invalid',
  ]) {
    test(
      'rejects unsafe search continuation $next before calling the client',
      () async {
        final api = home.FakeApi(searchPage());
        await expectLater(
          BuddiesRepo(apiService: api).search(
            query: BuddiesSearchQuery(city: 'Cairo'),
            next: next,
          ),
          throwsA(isA<ApiError>()),
        );
        expect(api.calls, 0);
      },
    );
  }

  test(
    'incomplete city text never calls Buddies even on refresh or filter Apply',
    () async {
      final api = home.FakeApi(searchPage(ids: [1]));
      final cubit = BuddiesSearchCubit(repo: BuddiesRepo(apiService: api));
      addTearDown(cubit.close);
      for (final text in ['', 'P', 'Paris', 'Paris, France']) {
        cubit.setCity(text);
        await cubit.refresh();
        cubit.apply(BuddiesFilters(gender: ['female']));
        await cubit.loadMore();
      }
      expect(api.calls, 0);
      expect(cubit.state.query, isNull);
    },
  );

  testWidgets(
    'clear cancels debounce and pending responses cannot restore results',
    (tester) async {
      final pending = Completer<dynamic>();
      final api = home.FakeApi(pending);
      final cubit = BuddiesSearchCubit(repo: BuddiesRepo(apiService: api));
      cubit.selectCity(testCity('Cairo'));
      final old = cubit.refresh();
      cubit.setCity('');
      pending.complete(searchPage(ids: [1]));
      await old;
      expect(cubit.state.items, isEmpty);
      expect(cubit.state.page, isNull);
      cubit.setCity('Bali');
      cubit.setCity(' ');
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.calls, 1);
      await cubit.close();
    },
  );

  testWidgets('typing invalidates old responses before the debounce fires', (
    tester,
  ) async {
    final pending = Completer<dynamic>();
    final api = home.FakeApi(pending);
    final cubit = BuddiesSearchCubit(repo: BuddiesRepo(apiService: api));
    cubit.selectCity(testCity('Old'));
    final old = cubit.refresh();
    cubit.setCity('New');
    pending.complete(searchPage(ids: [1]));
    await old;
    expect(cubit.state.items, isEmpty);
    expect(cubit.state.selectedCity, isNull);
    api.result = searchPage(ids: [2]);
    cubit.selectCity(testCity('New'));
    await cubit.refresh();
    expect(cubit.state.items.single.id, 2);
    expect(api.query!['city'], 'New');
    await cubit.close();
  });

  testWidgets(
    'Load more appends search results using the server continuation',
    (tester) async {
      final api = home.FakeApi(searchPage(ids: [1], next: '?page=2'));
      await showSearch(tester, api);
      await searchText(tester, 'Bali');
      api.result = searchPage(number: 2, ids: [1, 2]);
      await tester.ensureVisible(find.text('Load more'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(Uri.parse(api.path!).queryParameters['page'], '2');
      expect(Uri.parse(api.path!).queryParameters['city'], 'Bali');
      expect(find.text('Traveler 1'), findsOneWidget);
      expect(find.text('Traveler 2'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final fails in [false, true]) {
    test(
      'query changes ignore stale ${fails ? 'errors' : 'successes'} before and after the next request',
      () async {
        final pending = Completer<dynamic>();
        final api = home.FakeApi(pending);
        final cubit = BuddiesSearchCubit(repo: BuddiesRepo(apiService: api));
        addTearDown(cubit.close);
        cubit.selectCity(testCity('Old'));
        final old = cubit.refresh();
        api.result = searchPage(ids: [2]);
        cubit.selectCity(testCity('New'));
        await cubit.refresh();
        if (fails) {
          pending.completeError(
            ApiError(message: 'Old failure', statusCode: 401),
          );
        } else {
          pending.complete(searchPage(ids: [1]));
        }
        await old;
        expect(cubit.state.selectedCity!.cityName, 'New');
        expect(cubit.state.items.single.id, 2);
        expect(cubit.state.error, isNull);
      },
    );
  }

  test(
    'pagination deduplicates users, suppresses concurrent requests, retries failed links',
    () async {
      final api = home.FakeApi(searchPage(ids: [3, 1, 3], next: '?page=2'));
      final cubit = BuddiesSearchCubit(repo: BuddiesRepo(apiService: api));
      addTearDown(cubit.close);
      cubit.selectCity(testCity('Bali'));
      await cubit.refresh();
      expect(cubit.state.items.map((item) => item.id), [3, 1]);
      final pending = Completer<dynamic>();
      api.result = pending;
      final loading = cubit.loadMore();
      await cubit.loadMore();
      expect(api.calls, 2);
      pending.completeError(ApiError(message: 'Offline'));
      await loading;
      final failedLink = api.path;
      expect(cubit.state.items.length, 2);
      api.result = searchPage(number: 2, ids: [1, 2]);
      await cubit.loadMore();
      expect(api.path, failedLink);
      expect(cubit.state.items.map((item) => item.id), [3, 1, 2]);
      await cubit.loadMore();
      expect(api.calls, 3);
    },
  );

  test(
    'pagination rejects equivalent cycles without appending the bad page',
    () async {
      final api = home.FakeApi(searchPage(ids: [1], next: '?page=2'));
      final cubit = BuddiesSearchCubit(repo: BuddiesRepo(apiService: api));
      addTearDown(cubit.close);
      cubit.selectCity(testCity('Cairo'));
      await cubit.refresh();
      api.result = searchPage(
        number: 2,
        ids: [2],
        next: 'https://travibeapp.com/api/v1/buddies/search?page=2',
      );
      await cubit.loadMore();
      expect(cubit.state.items.single.id, 1);
      expect(cubit.state.error, isNotNull);
    },
  );

  test(
    'city, country and filters reload page one with stale pagination protection',
    () async {
      final api = home.FakeApi(searchPage(ids: [1], next: '?page=2'));
      final cubit = BuddiesSearchCubit(repo: BuddiesRepo(apiService: api));
      addTearDown(cubit.close);
      cubit.selectCity(testCity('Bali'));
      await cubit.refresh();
      final pending = Completer<dynamic>();
      api.result = pending;
      final old = cubit.loadMore();
      api.result = searchPage(ids: [8]);
      cubit.selectCity(testCity('Paris'));
      await cubit.refresh();
      pending.complete(searchPage(number: 2, ids: [2]));
      await old;
      expect(cubit.state.page!.currentPage, 1);
      expect(cubit.state.items.single.id, 8);
      expect(api.query!['city'], 'Paris');
      cubit.selectCity(testCity('Paris', code: 'FR', country: 'France'));
      await cubit.refresh();
      expect(api.query!['country_code'], 'FR');
      cubit.apply(BuddiesFilters(gender: ['female']));
      await cubit.refresh();
      expect(api.query!['gender[]'], ['female']);
      expect(cubit.state.page!.currentPage, 1);
      cubit.selectCity(
        testCity('London', code: 'GB', country: 'United Kingdom'),
      );
      await cubit.refresh();
      expect(api.query!['country_code'], 'GB');
      final calls = api.calls;
      cubit.apply(cubit.state.filters);
      cubit.selectCity(cubit.state.selectedCity!);
      expect(api.calls, calls);
    },
  );

  test('search filters stay independent from both listing Cubits', () async {
    final api = home.FakeApi(searchPage());
    final repo = BuddiesRepo(apiService: api);
    final search = BuddiesSearchCubit(repo: repo);
    final city = BuddiesListingCubit(listing: BuddiesListing.city, repo: repo);
    final interests = BuddiesListingCubit(
      listing: BuddiesListing.interests,
      repo: repo,
    );
    addTearDown(search.close);
    addTearDown(city.close);
    addTearDown(interests.close);
    search.apply(BuddiesFilters(gender: ['male']));
    expect(city.state.filters, BuddiesFilters());
    expect(interests.state.filters, BuddiesFilters());
    expect(api.calls, 0);
  });

  testWidgets(
    'session changes cancel timers, discard query/selections and reject old responses',
    (tester) async {
      final api = home.FakeApi(searchPage());
      final cubit = BuddiesSearchCubit(repo: BuddiesRepo(apiService: api));
      cubit.apply(BuddiesFilters(gender: ['male']));
      cubit.setCity('Cairo');
      await preferences.saveToken('other-account');
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.calls, 0);
      expect(cubit.state.text, '');
      expect(cubit.state.filters, BuddiesFilters());
      final pending = Completer<dynamic>();
      api.result = pending;
      cubit.selectCity(testCity('Bali'));
      final old = cubit.refresh();
      await preferences.clear();
      pending.complete(searchPage(ids: [1]));
      await old;
      expect(cubit.state.items, isEmpty);
      expect(cubit.state.text, '');
      cubit.selectCity(testCity('Bali'));
      await cubit.refresh();
      expect(api.calls, 1);
      expect(cubit.state.error!.statusCode, 401);
      await cubit.close();
    },
  );

  testWidgets('disposal cancels debounce and ignores a pending search', (
    tester,
  ) async {
    final api = home.FakeApi(searchPage());
    var cubit = BuddiesSearchCubit(repo: BuddiesRepo(apiService: api));
    cubit.setCity('Cairo');
    await cubit.close();
    await tester.pump(const Duration(milliseconds: 400));
    expect(api.calls, 0);
    final pending = Completer<dynamic>();
    api.result = pending;
    cubit = BuddiesSearchCubit(repo: BuddiesRepo(apiService: api));
    cubit.selectCity(testCity('Cairo'));
    final old = cubit.refresh();
    await cubit.close();
    pending.complete(searchPage(ids: [1]));
    await old;
    expect(cubit.state.items, isEmpty);
  });

  for (final status in [401, 403]) {
    test('search $status discards results and pagination', () async {
      final api = home.FakeApi(searchPage(ids: [1], next: '?page=2'));
      final cubit = BuddiesSearchCubit(repo: BuddiesRepo(apiService: api));
      addTearDown(cubit.close);
      cubit.selectCity(testCity('Cairo'));
      await cubit.refresh();
      api.result = ApiError(message: 'Denied', statusCode: status);
      await cubit.loadMore();
      expect(cubit.state.items, isEmpty);
      expect(cubit.state.page, isNull);
      expect(cubit.state.error!.statusCode, status);
    });
  }

  testWidgets(
    'Home opens search without an empty request, Back restores Home',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final api = home.FakeApi(home.home());
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: BuddiesScreen(repo: BuddiesRepo(apiService: api)),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.calls, 1);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Choose Destination'))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        true,
      );
      semantics.dispose();
      await tester.tap(find.text('Choose Destination'));
      await tester.pumpAndSettle();
      expect(find.byType(BuddiesSearchScreen), findsOneWidget);
      expect(find.text('Choose Destination'), findsWidgets);
      expect(api.calls, 1);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(BuddiesScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'input remains responsive, enforces length and clear removes results',
    (tester) async {
      final api = home.FakeApi(searchPage(ids: [1]));
      await showSearch(tester, api);
      expect(
        tester.widget<TextField>(find.byType(TextField)).decoration!.hintText,
        'Choose Destination',
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).decoration!.labelText,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'Bali');
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Bali',
      );
      expect(api.calls, 0);
      expect(find.byType(BuddiesSearchSkeleton), findsNothing);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(api.calls, 0);
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      expect(find.text('Traveler 1'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.byType(BuddiesTravelerCard), findsNothing);
      expect(api.calls, 1);
      await tester.enterText(find.byType(TextField), 'x' * 121);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byType(TextField))
            .controller!
            .text
            .length,
        120,
      );
      expect(api.calls, 1);
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      expect((api.query!['city'] as String).length, 120);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'empty, loading skeleton, error and retry use real request state',
    (tester) async {
      final pending = Completer<dynamic>();
      final api = home.FakeApi(pending);
      await showSearch(tester, api);
      await tester.enterText(find.byType(TextField), 'Cairo');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListTile).first);
      await tester.pump();
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(find.byType(BuddiesTravelerCard), findsNothing);
      pending.completeError(ApiError(message: 'Offline'));
      await tester.pumpAndSettle();
      expect(find.text('Offline'), findsOneWidget);
      api.result = searchPage();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('No buddies found in this city yet.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Paris search renders current-city people without a trip object',
    (tester) async {
      final data = searchPage(ids: [1]);
      final person = (data['data'] as List).single as Map<String, dynamic>;
      person.addAll({
        'city': 'Paris',
        'country_code': 'FR',
        'is_following': true,
        'shared_interests_count': 2,
      });
      final api = home.FakeApi(data);
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: BuddiesSearchScreen(
            repo: BuddiesRepo(apiService: api),
            placesProvider: FakeCityPlaces()
              ..onResolve = (suggestion) async => CitySelection(
                cityName: 'Paris',
                countryName: 'France',
                countryCode: 'FR',
                latitude: 0,
                longitude: 0,
              ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final cubit = tester
          .element(find.byType(TextField))
          .read<BuddiesSearchCubit>();
      await searchText(tester, '  Paris  ');
      expect(api.path, 'buddies/search');
      expect(api.query, {
        'city': 'Paris',
        'country_code': 'FR',
        'page': 1,
        'per_page': 15,
      });
      expect(cubit.state.items.single.isFollowing, true);
      expect(cubit.state.items.single.sharedInterestsCount, 2);
      expect(person.containsKey('trip'), false);
      expect(find.text('Paris, FR'), findsOneWidget);
      final card = tester.widget<BuddiesTravelerCard>(
        find.byType(BuddiesTravelerCard),
      );
      expect(card.traveler.dateLabel, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'cards show current city and no dates even if a legacy trip is present',
    (tester) async {
      final data = searchPage(ids: [1, 2]);
      (data['data'] as List)[0]['trip'] = {
        'destination_city': 'Bali',
        'destination_country_code': 'ID',
        'starts_on': '2026-11-01',
        'ends_on': null,
      };
      (data['data'] as List)[0]['city'] = 'Cairo';
      (data['data'] as List)[1]['interests'] = null;
      await showSearch(tester, home.FakeApi(data));
      (data['data'] as List)[0]['country_code'] = 'EG';
      await searchText(tester, 'Cairo');
      expect(find.text('Cairo, EG'), findsOneWidget);
      expect(find.text('Bali, ID'), findsNothing);
      expect(find.text('2026-11-01'), findsNothing);
      final cards = tester
          .widgetList<BuddiesTravelerCard>(find.byType(BuddiesTravelerCard))
          .toList();
      expect(cards[1].traveler.destination, isNull);
      expect(cards.every((card) => card.traveler.dateLabel == null), true);
      expect(cards[1].traveler.interests, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Filters Apply, Reset and Back retain search text and applied selections',
    (tester) async {
      final api = home.FakeApi(searchPage(ids: [1]));
      await showSearch(tester, api);
      await searchText(tester, 'Bali, Indonesia');
      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Female'));
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(api.query!['city'], 'Bali');
      expect(api.query!['gender[]'], ['female']);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Bali, Indonesia',
      );
      final calls = api.calls;
      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      expect(find.byType(BuddiesFiltersScreen), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Female'),
            )
            .value,
        true,
      );
      await tester.tap(find.text('Reset'));
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(api.calls, calls);
      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset'));
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(api.query!.containsKey('gender[]'), false);
      expect(api.query!['city'], 'Bali');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'current-city search has no sorting control and preserves backend order',
    (tester) async {
      final api = home.FakeApi(searchPage(ids: [3, 1]));
      await showSearch(tester, api);
      await searchText(tester, 'Cairo');
      expect(find.byType(DropdownButton), findsNothing);
      expect(find.text('Soonest'), findsNothing);
      expect(find.text('Newest'), findsNothing);
      expect(api.query!.containsKey('sort'), false);
      expect(
        tester
            .widgetList<BuddiesTravelerCard>(find.byType(BuddiesTravelerCard))
            .map((card) => card.traveler.id),
        ['3', '1'],
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'blocks hide current and late search results; logout clears input',
    (tester) async {
      final follow = FollowCubit();
      final blocks = home.TestBlockCubit(follow);
      final pending = Completer<dynamic>();
      final api = home.FakeApi(pending);
      await showSearch(tester, api, blocks: blocks);
      await tester.enterText(find.byType(TextField), 'Cairo');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListTile).first);
      await tester.pump();
      blocks.blockForTest('1');
      pending.complete(searchPage(ids: [1, 2]));
      await tester.pumpAndSettle();
      expect(find.text('Traveler 1'), findsNothing);
      expect(find.text('Traveler 2'), findsOneWidget);
      blocks.blockForTest('2');
      await tester.pumpAndSettle();
      expect(find.text('Traveler 2'), findsNothing);
      await preferences.clear();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
      expect(find.byType(BuddiesTravelerCard), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await blocks.close();
      await follow.close();
    },
  );

  testWidgets('Home search route shares existing BlockCubit', (tester) async {
    final follow = FollowCubit();
    final blocks = home.TestBlockCubit(follow)..blockForTest('1');
    final api = home.FakeApi(home.home());
    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        home: BlocProvider<BlockCubit>.value(
          value: blocks,
          child: RepositoryProvider<CityPlacesProvider>.value(
            value: FakeCityPlaces(),
            child: BuddiesScreen(repo: BuddiesRepo(apiService: api)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose Destination'));
    await tester.pumpAndSettle();
    api.result = searchPage(ids: [1]);
    await searchText(tester, 'Cairo');
    expect(find.byType(BuddiesTravelerCard), findsNothing);
    expect(find.text('No buddies found in this city yet.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await blocks.close();
    await follow.close();
  });

  testWidgets('narrow search and skeleton support 2x text without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = home.FakeApi(searchPage(ids: [1, 2]));
    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: BuddiesSearchScreen(
            repo: BuddiesRepo(apiService: api),
            placesProvider: FakeCityPlaces(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Cairo');
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
