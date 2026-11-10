import 'package:travibe/core/reference/countries_repo.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/buddies/data/buddies_filters.dart';
import 'package:travibe/features/buddies/data/buddies_page.dart';
import 'package:travibe/features/buddies/data/buddies_repo.dart';
import 'package:travibe/features/buddies/cubit/buddies_listing_cubit.dart';
import 'package:travibe/features/buddies/screens/buddies_screen.dart';
import 'package:travibe/features/buddies/screens/buddies_listing_screen.dart';
import 'package:travibe/features/buddies/screens/buddies_filters_screen.dart';
import 'package:travibe/features/buddies/widgets/buddies_traveler_card.dart';
import 'package:travibe/features/profilesetup/data/profile_setup_repo.dart';
import 'package:travibe/features/profilesetup/data/reference_item.dart';
import 'buddies_home_test.dart' as fixtures;

Map<String, dynamic> page({
  int number = 1,
  List<int> ids = const [],
  String? next,
  bool city = true,
}) => {
  'data': [
    for (final id in ids) {...fixtures.buddy(id: id), 'name': 'Traveler $id'},
  ],
  'links': {'first': null, 'last': null, 'prev': null, 'next': next},
  'meta': {
    'current_page': number,
    'from': null,
    'last_page': 3,
    'links': [],
    'path': null,
    'per_page': 15,
    'to': null,
    'total': 30,
    'has_current_city': city,
    'current_city': city ? {'city': null, 'country_code': null} : null,
  },
};

class CatalogRepo extends ProfileSetupRepo {
  @override
  Future<List<ReferenceCountry>> loadCountries(String locale) async => [];
  bool fail = false;
  @override
  Future<List<ReferenceItem>> loadCatalog(ReferenceKind kind) async {
    if (fail) throw ApiError(message: 'Offline');
    return [
      ReferenceItem(
        slug: 'verified-${kind.name}',
        name: kind.name,
        nameEn: kind.name,
        nameAr: kind.name,
      ),
    ];
  }
}

class RouteApi extends fixtures.FakeApi {
  RouteApi() : super(null);
  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
    path = endpoint;
    if (endpoint == 'buddies') {
      return {
        'data': {
          'in_your_city': [fixtures.buddy()],
          'with_same_interests': [fixtures.buddy()],
        },
        'meta': {
          'profile_completed': true,
          'show_in_travel_buddy': true,
          'has_current_city': true,
          'current_city': {'city': 'Cairo', 'country_code': null},
        },
      };
    }
    return page(ids: [8]);
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
    await preferences.saveToken('listing-test');
  });
  tearDown(() => preferences.clear());

  test('parses nullable resources and city-specific metadata', () {
    final result = BuddiesPage.fromJson(page(ids: [1]), BuddiesListing.city);
    expect(result.items.single.avatarUrl, isNull);
    expect(result.items.single.trip, isNull);
    expect(result.items.single.interests, isEmpty);
    expect(result.city, isNull);
    expect(result.countryCode, isNull);
    expect(result.hasCurrentCity, true);
    expect(result.perPage, 15);
    expect(result.links['next'], isNull);
    final shared = page()
      ..['meta'] = {
        'current_page': 1,
        'last_page': 1,
        'per_page': 15,
        'total': 0,
      };
    expect(
      BuddiesPage.fromJson(shared, BuddiesListing.interests).hasCurrentCity,
      isNull,
    );
  });
  test('malformed pagination is rejected', () {
    final bad = page();
    (bad['meta'] as Map)['current_page'] = '1';
    expect(
      () => BuddiesPage.fromJson(bad, BuddiesListing.city),
      throwsFormatException,
    );
    expect(
      () => BuddiesPage.fromJson({'data': []}, BuddiesListing.city),
      throwsFormatException,
    );
  });
  test(
    'serializes only selected verified filters; no invented initial page',
    () async {
      final api = fixtures.FakeApi(page());
      final filters = BuddiesFilters(
        gender: ['female'],
        nationality: ['EG'],
        languages: ['english'],
        interests: ['hiking'],
        travelStyles: ['solo'],
      );
      await BuddiesRepo(apiService: api).getInYourCity(filters: filters);
      expect(api.path, 'buddies/in-your-city');
      expect(api.query, {
        'per_page': 15,
        'gender[]': ['female'],
        'nationality[]': ['EG'],
        'languages[]': ['english'],
        'interests[]': ['hiking'],
        'travel_styles[]': ['solo'],
      });
      expect(() => BuddiesFilters(gender: ['other']), throwsArgumentError);
      expect(() => BuddiesFilters(nationality: ['Egypt']), throwsArgumentError);
      expect(BuddiesFilters().toQuery(), isEmpty);
    },
  );
  test('safe pagination keeps opaque cursor and applied filters', () async {
    final api = fixtures.FakeApi(page(number: 2));
    await BuddiesRepo(apiService: api).getWithSameInterests(
      next: '?cursor=server-token&per_page=15',
      filters: BuddiesFilters(gender: ['male']),
    );
    final uri = Uri.parse(api.path!);
    expect(uri.host, 'travibeapp.com');
    expect(uri.path, '/api/v1/buddies/with-same-interests');
    expect(uri.queryParameters['cursor'], 'server-token');
    expect(uri.queryParametersAll['gender[]'], ['male']);
    expect(api.query, isNull);
  });
  test(
    'pagination replaces indexed server filters with applied selections',
    () async {
      final api = fixtures.FakeApi(page(number: 2));
      await BuddiesRepo(apiService: api).getInYourCity(
        next: '?page=2&gender%5B0%5D=male&languages%5B%5D=old&per_page=25',
        filters: BuddiesFilters(
          gender: ['female'],
          languages: ['verified-slug'],
        ),
      );
      final query = Uri.parse(api.path!).queryParametersAll;
      expect(query['page'], ['2']);
      expect(query['per_page'], ['25']);
      expect(query['gender[]'], ['female']);
      expect(query['languages[]'], ['verified-slug']);
      expect(query.containsKey('gender[0]'), false);
    },
  );
  test('per_page boundaries are enforced before requesting', () async {
    final api = fixtures.FakeApi(page());
    final repo = BuddiesRepo(apiService: api);
    for (final value in [0, 101]) {
      await expectLater(
        repo.getInYourCity(perPage: value),
        throwsArgumentError,
      );
    }
    expect(api.calls, 0);
    for (final value in [1, 100]) {
      await repo.getInYourCity(perPage: value);
      expect(api.query!['per_page'], value);
    }
  });
  for (final link in [
    'https://evil.example/api/v1/buddies/in-your-city?x=1',
    'http://travibeapp.com/api/v1/buddies/in-your-city',
    'https://travibeapp.com/api/v1/profile',
    '//evil.example/x',
    'https://user:secret@travibeapp.com/api/v1/buddies/in-your-city',
    'https://travibeapp.com:444/api/v1/buddies/in-your-city',
    '?page=2#fragment',
    'https://[invalid',
  ]) {
    test('rejects unsafe next link $link before requesting', () async {
      final api = fixtures.FakeApi(page());
      await expectLater(
        BuddiesRepo(apiService: api).getInYourCity(next: link),
        throwsA(isA<ApiError>()),
      );
      expect(api.calls, 0);
    });
  }
  test(
    'pagination preserves ordering, deduplicates and prevents duplicate requests',
    () async {
      final api = fixtures.FakeApi(page(ids: [3, 1], next: '?page=2'));
      final cubit = BuddiesListingCubit(
        listing: BuddiesListing.city,
        repo: BuddiesRepo(apiService: api),
      );
      addTearDown(cubit.close);
      await cubit.refresh();
      final pending = Completer<dynamic>();
      api.result = pending;
      final loading = cubit.loadMore();
      await cubit.loadMore();
      expect(api.calls, 2);
      pending.complete(page(number: 2, ids: [1, 2]));
      await loading;
      expect(cubit.state.items.map((item) => item.id), [3, 1, 2]);
      await cubit.loadMore();
      expect(api.calls, 2);
    },
  );
  test('concurrent refresh waits for the active request', () async {
    final pending = Completer<dynamic>();
    final api = fixtures.FakeApi(pending);
    final cubit = BuddiesListingCubit(
      listing: BuddiesListing.city,
      repo: BuddiesRepo(apiService: api),
    );
    addTearDown(cubit.close);
    final first = cubit.refresh();
    var finished = false;
    final second = cubit.refresh().then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(finished, false);
    expect(api.calls, 1);
    pending.complete(page(ids: [1]));
    await Future.wait([first, second]);
    expect(finished, true);
  });
  test(
    'no-city response cannot load more even with a server next link',
    () async {
      final api = fixtures.FakeApi(
        page(ids: [1], city: false, next: '?page=2'),
      );
      final cubit = BuddiesListingCubit(
        listing: BuddiesListing.city,
        repo: BuddiesRepo(apiService: api),
      );
      addTearDown(cubit.close);
      await cubit.refresh();
      await cubit.loadMore();
      expect(api.calls, 1);
      expect(cubit.state.items, isEmpty);
    },
  );
  test(
    'equivalent relative and absolute continuation loops are rejected',
    () async {
      final api = fixtures.FakeApi(page(ids: [1], next: '?page=2&per_page=15'));
      final cubit = BuddiesListingCubit(
        listing: BuddiesListing.city,
        repo: BuddiesRepo(apiService: api),
      );
      addTearDown(cubit.close);
      await cubit.refresh();
      api.result = page(
        number: 2,
        ids: [2],
        next:
            'https://travibeapp.com/api/v1/buddies/in-your-city?per_page=15&page=2',
      );
      await cubit.loadMore();
      expect(cubit.state.error, isNotNull);
      expect(cubit.state.items.single.id, 1);
    },
  );
  test('pagination cannot move backwards to an unseen page', () async {
    final api = fixtures.FakeApi(page(ids: [1], next: '?cursor=next'));
    final cubit = BuddiesListingCubit(
      listing: BuddiesListing.interests,
      repo: BuddiesRepo(apiService: api),
    );
    addTearDown(cubit.close);
    await cubit.refresh();
    api.result = page(number: 3, ids: [3], next: '?cursor=back');
    await cubit.loadMore();
    api.result = page(number: 2, ids: [2]);
    await cubit.loadMore();
    expect(cubit.state.error, isNotNull);
    expect(cubit.state.items.map((item) => item.id), [1, 3]);
  });
  for (final status in [401, 403]) {
    test('listing $status clears records and pagination', () async {
      final api = fixtures.FakeApi(page(ids: [1], next: '?page=2'));
      final cubit = BuddiesListingCubit(
        listing: BuddiesListing.city,
        repo: BuddiesRepo(apiService: api),
      );
      addTearDown(cubit.close);
      await cubit.refresh();
      api.result = ApiError(message: 'Denied', statusCode: status);
      await cubit.loadMore();
      expect(cubit.state.items, isEmpty);
      expect(cubit.state.page, isNull);
      expect(cubit.state.error!.statusCode, status);
    });
  }
  test(
    'logout clears filters and records and rejects pending pagination',
    () async {
      final api = fixtures.FakeApi(page(ids: [1], next: '?page=2'));
      final cubit = BuddiesListingCubit(
        listing: BuddiesListing.city,
        repo: BuddiesRepo(apiService: api),
      );
      addTearDown(cubit.close);
      await cubit.apply(BuddiesFilters(gender: ['female']));
      final pending = Completer<dynamic>();
      api.result = pending;
      final loading = cubit.loadMore();
      await preferences.clear();
      pending.complete(page(number: 2, ids: [2]));
      await loading;
      expect(api.calls, 2);
      expect(cubit.state.items, isEmpty);
      expect(cubit.state.filters, BuddiesFilters());
      expect(cubit.state.error!.statusCode, 401);
    },
  );
  test('filters reset pagination and ignore the old response', () async {
    final pending = Completer<dynamic>();
    final api = fixtures.FakeApi(pending);
    final cubit = BuddiesListingCubit(
      listing: BuddiesListing.city,
      repo: BuddiesRepo(apiService: api),
    );
    addTearDown(cubit.close);
    final old = cubit.refresh();
    api.result = page(ids: [9]);
    await cubit.apply(BuddiesFilters(gender: ['female']));
    pending.complete(page(ids: [1]));
    await old;
    expect(cubit.state.items.single.id, 9);
    expect(cubit.state.filters.gender, {'female'});
    expect(api.query!['gender[]'], ['female']);
  });
  test('session change and disposal reject old requests', () async {
    final pending = Completer<dynamic>();
    final api = fixtures.FakeApi(pending);
    final cubit = BuddiesListingCubit(
      listing: BuddiesListing.city,
      repo: BuddiesRepo(apiService: api),
    );
    final old = cubit.refresh();
    api.result = page(ids: [2]);
    await preferences.saveToken('new-account');
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.items.single.id, 2);
    await cubit.close();
    pending.complete(page(ids: [1]));
    await old;
    expect(cubit.state.items.single.id, 2);
  });
  test(
    'no city suppresses traveler records and API errors can retry',
    () async {
      final api = fixtures.FakeApi(ApiError(message: 'Offline'));
      final cubit = BuddiesListingCubit(
        listing: BuddiesListing.city,
        repo: BuddiesRepo(apiService: api),
      );
      addTearDown(cubit.close);
      await cubit.refresh();
      expect(cubit.state.error!.message, 'Offline');
      api.result = page(ids: [1], city: false);
      await cubit.refresh();
      expect(cubit.state.items, isEmpty);
      expect(cubit.state.page!.hasCurrentCity, false);
    },
  );
  test(
    'failed load more preserves records and retries the same server link',
    () async {
      final api = fixtures.FakeApi(page(ids: [1], next: '?page=2'));
      final cubit = BuddiesListingCubit(
        listing: BuddiesListing.city,
        repo: BuddiesRepo(apiService: api),
      );
      addTearDown(cubit.close);
      await cubit.refresh();
      api.result = ApiError(message: 'Offline');
      await cubit.loadMore();
      expect(cubit.state.items.single.id, 1);
      final path = api.path;
      api.result = page(number: 2, ids: [2]);
      await cubit.loadMore();
      expect(api.path, path);
      expect(cubit.state.items.map((item) => item.id), [1, 2]);
    },
  );

  for (final listing in BuddiesListing.values) {
    testWidgets('${listing.title} matches listing grid and controls', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = fixtures.FakeApi(page(ids: [1, 2, 3]));
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 844),
              padding: EdgeInsets.only(top: 44, bottom: 34),
            ),
            child: BuddiesListingScreen(
              listing: listing,
              repo: BuddiesRepo(apiService: api),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final filters = tester.getRect(
        find.widgetWithText(FilledButton, 'Filters'),
      );
      expect(filters.left, 20);
      expect(filters.top, 136);
      expect(filters.height, 44);
      final first = tester.getRect(find.byType(BuddiesTravelerCard).at(0));
      final second = tester.getRect(find.byType(BuddiesTravelerCard).at(1));
      expect(first.left, 20);
      expect(first.top, 204);
      expect(first.width, 167);
      expect(second.left, 203);
      expect(second.top, first.top);
      expect(find.byTooltip('Back'), findsOneWidget);
      final title = tester.widget<Text>(find.text(listing.title));
      expect(title.style!.decoration, TextDecoration.none);
      final filterButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Filters'),
      );
      expect(
        filterButton.style!.textStyle!.resolve({})!.fontFamily,
        darkTheme.textTheme.labelLarge!.fontFamily,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('${listing.title} supports narrow screens with large text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: BuddiesListingScreen(
              listing: listing,
              repo: BuddiesRepo(
                apiService: fixtures.FakeApi(page(ids: [1, 2, 3])),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Back'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('See All opens ${listing.title}', (tester) async {
      final api = RouteApi();
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: BuddiesScreen(repo: BuddiesRepo(apiService: api)),
        ),
      );
      await tester.pumpAndSettle();
      final buttons = find.widgetWithText(TextButton, 'See All');
      await tester.ensureVisible(buttons.at(listing.index));
      await tester.tap(buttons.at(listing.index));
      await tester.pumpAndSettle();
      expect(find.byType(BuddiesListingScreen), findsOneWidget);
      expect(find.text(listing.title), findsOneWidget);
      expect(api.path, listing.endpoint);
      expect(find.text('Traveler 8'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('listing empty/error/retry and block filtering', (tester) async {
    final api = fixtures.FakeApi(ApiError(message: 'Offline'));
    final follow = FollowCubit();
    final block = fixtures.TestBlockCubit(follow);
    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        home: BlocProvider<BlockCubit>.value(
          value: block,
          child: BuddiesListingScreen(
            listing: BuddiesListing.city,
            repo: BuddiesRepo(apiService: api),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Offline'), findsOneWidget);
    api.result = page(ids: [1]);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Traveler 1'), findsOneWidget);
    block.blockForTest('1');
    await tester.pumpAndSettle();
    expect(find.text('Traveler 1'), findsNothing);
    expect(find.text('No travelers found.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await block.close();
    await follow.close();
  });
  testWidgets('filter drafts apply verified slugs and Reset does not commit', (
    tester,
  ) async {
    BuddiesFilters? applied;
    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                applied = await Navigator.push<BuddiesFilters>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BuddiesFiltersScreen(
                      initial: BuddiesFilters(gender: ['male']),
                      catalogRepo: CatalogRepo(),
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(applied, isNull);
    await tester.tap(find.text('Female'));
    await tester.ensureVisible(find.text('languages'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('languages'));
    await tester.tap(find.text('languages'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(applied!.gender, {'female'});
    expect(applied!.languages, {'verified-languages'});
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'filters support narrow screens and catalog errors without fake options',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = CatalogRepo()..fail = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: BuddiesFiltersScreen(
              initial: BuddiesFilters(),
              catalogRepo: repo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('English'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Back discards filter draft; session changes close the filter screen',
    (tester) async {
      BuddiesFilters? result;
      Future<void> open(WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: darkTheme,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await Navigator.push<BuddiesFilters>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BuddiesFiltersScreen(
                          initial: BuddiesFilters(),
                          catalogRepo: CatalogRepo(),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open filters'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open filters'));
        await tester.pumpAndSettle();
      }

      await open(tester);
      await tester.tap(find.text('Female'));
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      await tester.tap(find.text('Open filters'));
      await tester.pumpAndSettle();
      await preferences.clear();
      await tester.pumpAndSettle();
      expect(find.byType(BuddiesFiltersScreen), findsNothing);
      expect(result, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'cyclic pagination returns error without appending duplicate page',
    () async {
      final api = fixtures.FakeApi(page(ids: [1], next: '?page=2'));
      final cubit = BuddiesListingCubit(
        listing: BuddiesListing.city,
        repo: BuddiesRepo(apiService: api),
      );
      addTearDown(cubit.close);
      await cubit.refresh();
      api.result = page(number: 2, ids: [2], next: '?page=2');
      await cubit.loadMore();
      expect(cubit.state.error, isNotNull);
      expect(cubit.state.items.map((item) => item.id), [1]);
    },
  );
}
