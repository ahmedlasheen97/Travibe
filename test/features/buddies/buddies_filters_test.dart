import 'package:flutter/cupertino.dart';
import 'package:travibe/core/reference/countries_repo.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/buddies/cubit/buddies_listing_cubit.dart';
import 'package:travibe/features/buddies/data/buddies_filters.dart';
import 'package:travibe/features/buddies/data/buddies_repo.dart';
import 'package:travibe/features/buddies/screens/buddies_filters_screen.dart';
import 'package:travibe/features/buddies/screens/buddies_listing_screen.dart';
import 'package:travibe/features/profilesetup/data/profile_setup_repo.dart';
import 'package:travibe/features/profilesetup/data/reference_item.dart';
import 'buddies_home_test.dart' as home;
import 'buddies_listing_test.dart' as listing;

// Test-only catalog labels deliberately differ from slugs.
class FilterCatalog extends ProfileSetupRepo {
  @override
  Future<List<ReferenceCountry>> loadCountries(String locale) async => [
    ReferenceCountry(
      code: 'EG',
      name: locale == 'ar' ? 'مصر' : 'Egypt',
      nameEn: 'Egypt',
      nameAr: 'مصر',
    ),
    const ReferenceCountry(
      code: 'FR',
      name: 'France',
      nameEn: 'France',
      nameAr: 'فرنسا',
    ),
    const ReferenceCountry(
      code: 'IT',
      name: 'Italy',
      nameEn: 'Italy',
      nameAr: 'إيطاليا',
    ),
  ];
  bool fail = false;
  bool empty = false;
  int count = 2;
  final Map<ReferenceKind, Completer<List<ReferenceItem>>> pending = {};
  final Map<ReferenceKind, int> calls = {};
  @override
  Future<List<ReferenceItem>> loadCatalog(ReferenceKind kind) async {
    calls[kind] = (calls[kind] ?? 0) + 1;
    if (pending.containsKey(kind)) return pending[kind]!.future;
    if (fail) throw ApiError(message: 'Offline');
    return [
      if (!empty)
        for (var i = 0; i < count; i++)
          ReferenceItem(
            slug: '${kind.name}-$i',
            name: '${kind.name} option $i',
            nameEn: '${kind.name} option $i',
            nameAr: '${kind.name} option $i',
          ),
    ];
  }
}

class DraftHost {
  DraftHost(this.applied, this.catalog);
  BuddiesFilters applied;
  final ProfileSetupRepo catalog;
  int commits = 0;
  Widget build() => MaterialApp(
    theme: darkTheme,
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            final result = await Navigator.push<BuddiesFilters>(
              context,
              MaterialPageRoute(
                builder: (_) => BuddiesFiltersScreen(
                  initial: applied,
                  catalogRepo: catalog,
                ),
              ),
            );
            if (result != null) {
              applied = result;
              commits++;
            }
          },
          child: const Text('Open filters'),
        ),
      ),
    ),
  );
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 160);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> openDraft(WidgetTester tester, DraftHost host) async {
  await tester.pumpWidget(host.build());
  await tester.tap(find.text('Open filters'));
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
    await preferences.saveToken('filter-tests');
  });
  tearDown(() => preferences.clear());

  test(
    'multi-value serialization uses exact array keys and immutable sets',
    () {
      final filters = BuddiesFilters(
        gender: ['male', 'female', 'male'],
        nationality: ['EG', 'IT'],
        languages: ['language-a', 'language-b'],
        interests: ['interest-a', 'interest-b'],
        travelStyles: ['style-a', 'style-b'],
      );
      expect(filters.toQuery(), {
        'gender[]': ['male', 'female'],
        'nationality[]': ['EG', 'IT'],
        'languages[]': ['language-a', 'language-b'],
        'interests[]': ['interest-a', 'interest-b'],
        'travel_styles[]': ['style-a', 'style-b'],
      });
      expect(() => filters.gender.add('male'), throwsUnsupportedError);
      expect(BuddiesFilters().toQuery(), isEmpty);
    },
  );

  testWidgets(
    'all categories allow multiple choices and reopening restores applied values',
    (tester) async {
      final host = DraftHost(
        BuddiesFilters(nationality: ['EG', 'IT']),
        FilterCatalog(),
      );
      await openDraft(tester, host);
      await tapVisible(tester, find.text('Male'));
      await tapVisible(tester, find.text('Female'));
      for (final kind in ReferenceKind.values) {
        for (var i = 0; i < 2; i++) {
          await tapVisible(tester, find.text('${kind.name} option $i'));
        }
      }
      expect(host.commits, 0);
      expect(host.applied.gender, isEmpty);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(host.applied.gender, {'male', 'female'});
      expect(host.applied.nationality, {'EG', 'IT'});
      expect(host.applied.languages, {'languages-0', 'languages-1'});
      expect(host.applied.interests, {'interests-0', 'interests-1'});
      expect(host.applied.travelStyles, {'travelStyles-0', 'travelStyles-1'});
      await tester.tap(find.text('Open filters'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<InputChip>(find.widgetWithText(InputChip, 'Egypt'))
            .labelStyle!
            .decoration,
        TextDecoration.none,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Male'),
            )
            .value,
        true,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Female'),
            )
            .value,
        true,
      );
      for (final kind in ReferenceKind.values) {
        for (var i = 0; i < 2; i++) {
          final chip = find.widgetWithText(
            FilterChip,
            '${kind.name} option $i',
          );
          if (chip.evaluate().isEmpty) {
            await tester.scrollUntilVisible(chip, 160);
          }
          await tester.ensureVisible(chip);
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<FilterChip>(
                  find.widgetWithText(FilterChip, '${kind.name} option $i'),
                )
                .selected,
            true,
          );
        }
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Reset is draft-only, Back discards it, Apply clears all query values',
    (tester) async {
      final initial = BuddiesFilters(
        gender: ['female'],
        nationality: ['EG'],
        languages: ['languages-0'],
        interests: ['interests-0'],
        travelStyles: ['travelStyles-0'],
      );
      final host = DraftHost(initial, FilterCatalog());
      await openDraft(tester, host);
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(host.applied, initial);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(host.commits, 0);
      await tester.tap(find.text('Open filters'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Female'),
            )
            .value,
        true,
      );
      await tester.tap(find.text('Reset'));
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(host.applied.toQuery(), isEmpty);
      expect(host.commits, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'nationality dropdown adds distinct countries and chips remove them',
    (tester) async {
      final host = DraftHost(BuddiesFilters(), FilterCatalog());
      await openDraft(tester, host);
      for (final country in ['Egypt', 'Italy']) {
        await tapVisible(tester, find.text('Select nationality'));
        await tester.enterText(find.byType(TextField), country);
        await tester.pumpAndSettle();
        await tester.tap(find.text(country).last);
        await tester.pumpAndSettle();
      }
      final chip = find.widgetWithText(InputChip, 'Egypt');
      await tester.ensureVisible(chip);
      await tester.tap(
        find.descendant(of: chip, matching: find.byIcon(Icons.cancel_outlined)),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(InputChip, 'Egypt'), findsNothing);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(host.applied.nationality, {'IT'});
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Show Less/More retains hidden selections and fixed footer', (
    tester,
  ) async {
    final host = DraftHost(BuddiesFilters(), FilterCatalog()..count = 8);
    await openDraft(tester, host);
    final applyBefore = tester.getRect(find.text('Apply'));
    await tapVisible(tester, find.text('interests option 7'));
    // Languages also has an independent expansion control.
    final interestToggle = find
        .ancestor(
          of: find.text('interests option 7'),
          matching: find.byType(Column),
        )
        .first;
    await tapVisible(
      tester,
      find.descendant(of: interestToggle, matching: find.text('Show Less')),
    );
    expect(find.text('interests option 7'), findsNothing);
    expect(tester.getRect(find.text('Apply')), applyBefore);
    await tapVisible(tester, find.text('Show More').last);
    expect(
      tester
          .widget<FilterChip>(
            find.widgetWithText(FilterChip, 'interests option 7'),
          )
          .selected,
      true,
    );
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(host.applied.interests, {'interests-7'});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Travel Style expansion and selections have no profile-setup count limit',
    (tester) async {
      final host = DraftHost(BuddiesFilters(), FilterCatalog()..count = 8);
      await openDraft(tester, host);
      for (var i = 0; i < 8; i++) {
        await tapVisible(tester, find.text('travelStyles option $i'));
      }
      final group = find
          .ancestor(
            of: find.text('travelStyles option 7'),
            matching: find.byType(Column),
          )
          .first;
      await tapVisible(
        tester,
        find.descendant(of: group, matching: find.text('Show Less')),
      );
      expect(find.text('travelStyles option 7'), findsNothing);
      await tapVisible(tester, find.text('Show More').last);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(host.applied.travelStyles.length, 8);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'narrow filter layout keeps footer usable with large text and missing selections',
    (tester) async {
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
            child: BuddiesFiltersScreen(
              initial: BuddiesFilters(
                nationality: ['EG', 'IT'],
                languages: ['previous-language'],
              ),
              catalogRepo: FilterCatalog(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('Apply')).bottom, lessThanOrEqualTo(640));
      await tester.scrollUntilVisible(
        find.text('Selected: previous-language'),
        120,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<Text>(find.text('Filters')).style!.decoration,
        TextDecoration.none,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final empty in [true, false]) {
    testWidgets(
      'previously applied selections survive ${empty ? 'empty' : 'failed'} catalogs and remain removable',
      (tester) async {
        final catalog = FilterCatalog()
          ..empty = empty
          ..fail = !empty;
        final host = DraftHost(
          BuddiesFilters(
            languages: ['previous-language'],
            interests: ['previous-interest'],
          ),
          catalog,
        );
        await openDraft(tester, host);
        final chip = find.widgetWithText(
          InputChip,
          'Selected: previous-language',
        );
        // Invoke the chip's delete affordance without relying on its theme glyph.
        tester.widget<InputChip>(chip).onDeleted!();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();
        expect(host.applied.languages, isEmpty);
        expect(host.applied.interests, {'previous-interest'});
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'catalog loading, failure, retry and empty states are independent',
    (tester) async {
      final catalog = FilterCatalog()..fail = true;
      final pending = Completer<List<ReferenceItem>>();
      catalog.pending[ReferenceKind.languages] = pending;
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: BuddiesFiltersScreen(
            initial: BuddiesFilters(),
            catalogRepo: catalog,
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      pending.complete([]);
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(find.text('Options are unavailable.'), findsOneWidget);
      await tapVisible(tester, find.text('Retry Interests'));
      expect(catalog.calls[ReferenceKind.interests], 2);
      catalog.fail = false;
      await tapVisible(tester, find.text('Retry Interests'));
      expect(find.text('interests option 0'), findsOneWidget);
      expect(find.text('Retry Travel Style'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final selectedListing in BuddiesListing.values) {
    testWidgets(
      '${selectedListing.title}: Apply updates its request, reopening and Back preserve filters',
      (tester) async {
        final api = home.FakeApi(listing.page(ids: [1], next: '?page=2'));
        await tester.pumpWidget(
          MaterialApp(
            theme: darkTheme,
            home: BuddiesListingScreen(
              listing: selectedListing,
              repo: BuddiesRepo(apiService: api),
              catalogRepo: FilterCatalog(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final cubit = tester
            .element(find.text('Filters'))
            .read<BuddiesListingCubit>();
        await tapVisible(tester, find.text('Load more'));
        // A repeated page is rejected by Stage 2, then applying starts afresh.
        await tapVisible(tester, find.text('Filters'));
        await tapVisible(tester, find.text('Male'));
        await tapVisible(tester, find.text('Female'));
        api.result = listing.page();
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();
        expect(api.path, selectedListing.endpoint);
        expect(api.query, {
          'per_page': 15,
          'gender[]': ['male', 'female'],
        });
        expect(cubit.state.page!.currentPage, 1);
        expect(find.text('No travelers found.'), findsOneWidget);
        final calls = api.calls;
        await tapVisible(tester, find.text('Filters'));
        expect(
          tester
              .widget<CheckboxListTile>(
                find.widgetWithText(CheckboxListTile, 'Male'),
              )
              .value,
          true,
        );
        await tapVisible(tester, find.text('Female'));
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(api.calls, calls);
        expect(cubit.state.filters.gender, {'male', 'female'});
        await tapVisible(tester, find.text('Filters'));
        await tester.tap(find.text('Reset'));
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();
        expect(api.query, {'per_page': 15});
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  test(
    'listing filters are independent and pagination resets on Apply',
    () async {
      final cityApi = home.FakeApi(listing.page(ids: [1], next: '?page=2'));
      final interestsApi = home.FakeApi(
        listing.page(ids: [2], next: '?page=2'),
      );
      final city = BuddiesListingCubit(
        listing: BuddiesListing.city,
        repo: BuddiesRepo(apiService: cityApi),
      );
      final interests = BuddiesListingCubit(
        listing: BuddiesListing.interests,
        repo: BuddiesRepo(apiService: interestsApi),
      );
      addTearDown(city.close);
      addTearDown(interests.close);
      await city.refresh();
      await interests.refresh();
      cityApi.result = listing.page(number: 2, ids: [3]);
      await city.loadMore();
      cityApi.result = listing.page(ids: [4]);
      await city.apply(BuddiesFilters(gender: ['male']));
      await interests.apply(BuddiesFilters(gender: ['female']));
      expect(city.state.filters.gender, {'male'});
      expect(interests.state.filters.gender, {'female'});
      expect(city.state.items.single.id, 4);
      expect(city.state.page!.currentPage, 1);
      expect(cityApi.path, BuddiesListing.city.endpoint);
      expect(cityApi.query, {
        'per_page': 15,
        'gender[]': ['male'],
      });
      await city.apply(BuddiesFilters());
      expect(interests.state.filters.gender, {'female'});
    },
  );

  for (final fails in [false, true]) {
    test(
      'old pagination ${fails ? 'error' : 'success'} cannot overwrite filtered results',
      () async {
        final api = home.FakeApi(listing.page(ids: [1], next: '?page=2'));
        final cubit = BuddiesListingCubit(
          listing: BuddiesListing.city,
          repo: BuddiesRepo(apiService: api),
        );
        addTearDown(cubit.close);
        await cubit.refresh();
        final pending = Completer<dynamic>();
        api.result = pending;
        final old = cubit.loadMore();
        api.result = listing.page(ids: [9]);
        await cubit.apply(BuddiesFilters(interests: ['verified-interest']));
        if (fails) {
          pending.completeError(ApiError(message: 'Old failure'));
        } else {
          pending.complete(listing.page(number: 2, ids: [2]));
        }
        await old;
        expect(cubit.state.items.single.id, 9);
        expect(cubit.state.filters.interests, {'verified-interest'});
        expect(cubit.state.error, isNull);
        expect(cubit.state.page!.currentPage, 1);
      },
    );
  }
}
