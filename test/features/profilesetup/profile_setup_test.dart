import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/widgets/travibe_choice_chip.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/profilesetup/cubit/profile_setup_cubit.dart';
import 'package:travibe/features/profilesetup/data/profile_setup_repo.dart';
import 'package:travibe/core/widgets/custom_button.dart';
import 'package:travibe/features/profilesetup/widgets/setup_step_indicator.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/profilesetup/data/profile_selection_options.dart';
import 'package:travibe/features/profilesetup/data/reference_item.dart';
import 'package:travibe/features/profilesetup/widgets/step3_travel_style.dart';
import 'package:travibe/features/profilesetup/widgets/catalog_status_view.dart';
import 'package:travibe/features/profilesetup/widgets/step2_languages_interests.dart';

Map<String, dynamic> item(String slug, String name, {String? status}) => {
  'slug': slug,
  'name': name,
  'name_en': name,
  'name_ar': 'اسم $name',
  'status': ?status,
};

class FakeApi extends ApiService {
  final catalogs = <String, List<Map<String, dynamic>>>{
    'languages': [item('english', 'English', status: 'active')],
    'interests': [item('photography', 'Photography')],
    'travel-styles': [
      item('solo_traveler', 'Solo Traveler'),
      item('group_traveler', 'Group Traveler'),
      item('couple_escapes', 'Couple Escapes'),
      item('family_traveler', 'Family Traveler'),
    ],
  };
  final gets = <String>[];
  final patches = <Map<String, dynamic>>[];
  final posts = <String>[];
  ApiError? patchError;
  String? failedCatalog;

  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
    gets.add(endpoint);
    if (endpoint == 'profile/username-availability') {
      return {
        'data': {'username': queryParameters!['username'], 'available': true},
      };
    }
    if (endpoint == 'reference/$failedCatalog') {
      throw ApiError(message: 'Catalog unavailable');
    }
    return {'data': catalogs[endpoint.split('/').last]};
  }

  @override
  Future<dynamic> patch(String endpoint, Map<String, dynamic> data) async {
    expect(endpoint, 'profile/setup');
    if (patchError != null) throw patchError!;
    patches.add(data);
    return {
      'data': {'id': 7},
      'meta': {'profile_completed': false, 'profile_setup_step': 'review'},
    };
  }

  @override
  Future<dynamic> post(String endpoint, Map<String, dynamic> data) async {
    posts.add(endpoint);
    return {
      'data': {},
      'meta': {'profile_completed': true, 'profile_setup_step': 'complete'},
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeApi api;
  late ProfileSetupRepo repo;
  setUp(() {
    api = FakeApi();
    repo = ProfileSetupRepo(apiService: api);
  });

  test(
    'catalog parsing retains canonical keys, localized labels and language status',
    () {
      final values = ReferenceItem.parseCatalog({
        'data': [item('english', 'English', status: 'active')],
      });
      expect(values.single.slug, 'english');
      expect(values.single.label('en'), 'English');
      expect(values.single.label('ar'), 'اسم English');
      expect(values.single.status, 'active');
      expect(ReferenceItem.parseCatalog({'data': []}), isEmpty);
      expect(
        () => ReferenceItem.parseCatalog({
          'data': [
            {'name': 'English'},
          ],
        }),
        throwsA(isA<ApiError>()),
      );
      expect(
        () => ReferenceItem.parseCatalog({'data': 'invalid'}),
        throwsA(isA<ApiError>()),
      );
    },
  );

  test(
    'saves mapped slugs and fetches catalogs only for travel styles',
    () async {
      await repo.saveSetup(
        languages: ['english'],
        interests: ['photography'],
        travelStyles: ['solo_traveler'],
      );
      expect(api.patches.single, {
        'languages_spoken': ['english'],
        'interests': ['photography'],
        'travel_styles': ['solo_traveler'],
      });
      expect(api.gets, ['reference/travel-styles']);
      await expectLater(
        repo.saveSetup(travelStyles: ['Solo Traveler']),
        throwsA(isA<ApiError>()),
      );
      await repo.saveSetup(languages: ['English'], interests: ['Photography']);
      expect(api.patches.last, {
        'languages_spoken': ['english'],
        'interests': ['photography'],
      });
      expect(api.patches, hasLength(2));
    },
  );

  test('limits and duplicate selections cannot reach PATCH', () async {
    await expectLater(
      repo.saveSetup(
        travelStyles: [
          'solo_traveler',
          'group_traveler',
          'couple_escapes',
          'family_traveler',
        ],
      ),
      throwsA(isA<ApiError>()),
    );
    await expectLater(
      repo.saveSetup(languages: List.filled(5, 'english')),
      throwsA(isA<ApiError>()),
    );
    await expectLater(
      repo.saveSetup(interests: List.filled(7, 'photography')),
      throwsA(isA<ApiError>()),
    );
    await expectLater(
      repo.saveSetup(travelStyles: ['solo_traveler', 'solo_traveler']),
      throwsA(isA<ApiError>()),
    );
    expect(api.patches, isEmpty);
  });

  test('repository preserves backend error identity and HTTP status', () async {
    final failure = ApiError(
      message: 'The selected travel_styles.0 is invalid.',
      statusCode: 422,
    );
    api.patchError = failure;
    await expectLater(
      repo.saveSetup(travelStyles: ['solo_traveler']),
      throwsA(same(failure)),
    );
  });

  test(
    'startup fetches only travel styles and restored chips select without catalogs',
    () async {
      final cubit = ProfileSetupCubit(repo: repo);
      addTearDown(cubit.close);
      api.failedCatalog = 'languages';
      await cubit.loadCatalogs();
      expect(api.gets, ['reference/travel-styles']);
      cubit.setTravelStyles(['Solo Traveler']);
      expect(cubit.state.travelStyles, isEmpty);
      cubit.setTravelStyles(['solo_traveler']);
      expect(cubit.state.travelStyles, ['solo_traveler']);
      cubit.setLanguages(['English', 'Arabic', 'French', 'German']);
      cubit.setLanguages([
        'English',
        'Arabic',
        'French',
        'German',
        'Portuguese',
      ]);
      expect(cubit.state.languages, ['English', 'Arabic', 'French', 'German']);
      cubit.setInterests([
        'Hiking',
        'Photography',
        'Beach',
        'Culture',
        'Adventure',
        'Nightlife',
      ]);
      cubit.setInterests([
        'Hiking',
        'Photography',
        'Beach',
        'Culture',
        'Adventure',
        'Nightlife',
        'Food',
      ]);
      expect(cubit.state.interests, hasLength(6));
      cubit.setLanguages(['English']);
      expect(cubit.state.languages, ['English']);
      cubit.setLanguages(['Unsupported']);
      expect(cubit.state.languages, ['English']);
    },
  );

  test(
    'every original UI option has an explicit verified slug mapping',
    () async {
      expect(profileLanguageSlugs.keys.toList(), profileLanguageOptions);
      expect(profileInterestSlugs.keys.toList(), profileInterestOptions);
      const verifiedLanguages = {
        'arabic',
        'chinese',
        'english',
        'french',
        'german',
        'italian',
        'japanese',
        'korean',
        'portuguese',
        'russian',
        'spanish',
        'turkish',
      };
      const verifiedInterests = {
        'adventure',
        'art',
        'beach',
        'camping',
        'culture',
        'diving',
        'food',
        'hiking',
        'history',
        'luxury',
        'nature',
        'nightlife',
        'photography',
        'road_trips',
        'skiing',
        'surfing',
        'wellness',
        'wildlife',
      };
      expect(
        profileLanguageSlugs.values.every(verifiedLanguages.contains),
        isTrue,
      );
      expect(
        profileInterestSlugs.values.every(verifiedInterests.contains),
        isTrue,
      );
      for (final label in profileLanguageOptions) {
        await repo.saveSetup(languages: [label]);
        expect(api.patches.last, {
          'languages_spoken': [profileLanguageSlugs[label]],
        });
      }
      for (final label in profileInterestOptions) {
        await repo.saveSetup(interests: [label]);
        expect(api.patches.last, {
          'interests': [profileInterestSlugs[label]],
        });
      }
      expect(api.gets, isEmpty);
    },
  );

  test(
    'saving languages and interests succeeds even when catalogs are unavailable',
    () async {
      api.failedCatalog = 'languages';
      api.catalogs.clear();
      await repo.saveSetup(
        languages: ['English', 'Korean'],
        interests: ['Photography', 'Road Trips'],
      );
      expect(api.patches.single, {
        'languages_spoken': ['english', 'korean'],
        'interests': ['photography', 'road_trips'],
      });
      expect(api.gets, isEmpty);
    },
  );

  test(
    'unsupported options and duplicate aliases fail without API calls',
    () async {
      await expectLater(
        repo.saveSetup(languages: ['Unsupported']),
        throwsA(
          isA<ApiError>().having(
            (error) => error.message,
            'message',
            contains('Unsupported'),
          ),
        ),
      );
      await expectLater(
        repo.saveSetup(interests: ['Road-Trips']),
        throwsA(isA<ApiError>()),
      );
      await expectLater(
        repo.saveSetup(languages: ['English', 'english']),
        throwsA(isA<ApiError>()),
      );
      await expectLater(
        repo.saveSetup(interests: ['Photography', 'photography']),
        throwsA(isA<ApiError>()),
      );
      expect(api.gets, isEmpty);
      expect(api.patches, isEmpty);
    },
  );

  test(
    'omitted and empty selections retain their serialization behavior',
    () async {
      await repo.saveSetup(fullName: 'Sara');
      expect(api.patches.last, {'full_name': 'Sara'});
      await repo.saveSetup(languages: [], interests: []);
      expect(api.patches.last, {'languages_spoken': [], 'interests': []});
      expect(api.gets, isEmpty);
    },
  );

  test(
    'finish displays clean validation text and retains selections for retry',
    () async {
      final cubit = ProfileSetupCubit(repo: repo);
      addTearDown(cubit.close);
      await cubit.loadCatalogs();
      cubit.setTravelStyles(['solo_traveler']);
      api.patchError = ApiError(
        message: 'Travel style is no longer available.',
        statusCode: 422,
      );
      await cubit.finish();
      expect(cubit.state.status, ProfileSetupStatus.failure);
      expect(cubit.state.errorMessage, 'Travel style is no longer available.');
      expect(cubit.state.errorMessage, isNot(contains('ApiError')));
      expect(cubit.state.travelStyles, ['solo_traveler']);
      expect(api.posts, isEmpty);
    },
  );

  testWidgets('complete setup keeps save then complete ordering', (
    tester,
  ) async {
    final cubit = ProfileSetupCubit(repo: repo);
    addTearDown(cubit.close);
    await cubit.loadCatalogs();
    cubit.fullNameController.text = 'Sara';
    cubit.usernameController.text = 'sara';
    cubit.onUsernameChanged('sara');
    await tester.pump(const Duration(milliseconds: 501));
    await tester.pump();
    expect(cubit.state.usernameStatus, UsernameStatus.available);
    await cubit.saveBasicInfo();
    cubit.setLanguages(['English']);
    cubit.setInterests(['Photography']);
    await cubit.saveLanguagesAndInterests();
    cubit.setTravelStyles(['solo_traveler']);
    await cubit.finish();
    expect(cubit.state.status, ProfileSetupStatus.completed);
    expect(api.patches.last, {
      'travel_styles': ['solo_traveler'],
    });
    expect(api.posts, ['profile/setup/complete']);
    expect(api.patches[1], {
      'languages_spoken': ['english'],
      'interests': ['photography'],
    });
    expect(api.gets, [
      'reference/travel-styles',
      'profile/username-availability',
    ]);
  });

  testWidgets(
    'cards preserve order and selected styling while emitting backend slugs',
    (tester) async {
      final values = await repo.loadCatalog(ReferenceKind.travelStyles);
      var selected = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Step3TravelStyle(
                catalog: ReferenceCatalog(
                  status: CatalogStatus.loaded,
                  items: values.reversed.toList(),
                ),
                onRetry: () {},
                selectedTravelStyles: selected,
                onTravelStylesChanged: (value) =>
                    setState(() => selected = value),
                onFinish: () {},
                isSubmitting: false,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Solo Traveler'));
      await tester.pump();
      expect(selected, ['solo_traveler']);
      expect(
        tester.getTopLeft(find.text('Solo Traveler')).dx,
        lessThan(tester.getTopLeft(find.text('Group Traveler')).dx),
      );
      final containers = tester.widgetList<Container>(
        find.ancestor(
          of: find.text('Solo Traveler'),
          matching: find.byType(Container),
        ),
      );
      expect(
        containers.any(
          (container) =>
              container.decoration is BoxDecoration &&
              ((container.decoration! as BoxDecoration).border! as Border)
                      .top
                      .color ==
                  const Color(0xFFE45C10),
        ),
        isTrue,
      );
      await tester.tap(find.text('Solo Traveler'));
      await tester.pump();
      expect(selected, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('catalog status shows loading, empty and retryable errors', (
    tester,
  ) async {
    var retries = 0;
    Future<void> show(ReferenceCatalog catalog) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CatalogStatusView(catalog: catalog, onRetry: () => retries++),
        ),
      ),
    );
    await show(const ReferenceCatalog());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await show(const ReferenceCatalog(status: CatalogStatus.loaded));
    expect(find.text('No options are available right now.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await show(
      const ReferenceCatalog(
        status: CatalogStatus.failure,
        error: 'Catalog unavailable',
      ),
    );
    expect(find.text('Catalog unavailable'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retries, 2);
  });

  testWidgets(
    'restored language and interest chips toggle labels without catalog UI',
    (tester) async {
      var selectedLanguages = <String>[];
      var selectedInterests = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Step2LanguagesInterests(
                selectedLanguages: selectedLanguages,
                selectedInterests: selectedInterests,
                onLanguagesChanged: (value) =>
                    setState(() => selectedLanguages = value),
                onInterestsChanged: (value) =>
                    setState(() => selectedInterests = value),
                onNext: () {},
                onSkip: () {},
                isSaving: false,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('English'));
      await tester.pump();
      await tester.tap(find.text('Photography'));
      await tester.pump();
      expect(selectedLanguages, ['English']);
      expect(selectedInterests, ['Photography']);
      expect(find.byType(CatalogStatusView), findsNothing);
      expect(find.text('Invalid reference catalog response.'), findsNothing);
      expect(api.gets, isEmpty);
      await tester.tap(find.text('English'));
      await tester.pump();
      expect(selectedLanguages, isEmpty);
      await tester.tap(find.text('Photography'));
      await tester.pump();
      expect(selectedInterests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('step 2 matches Figma chips, spacing and Skip For Now', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Step2LanguagesInterests(
            selectedLanguages: const ['English'],
            selectedInterests: const ['Hiking'],
            onLanguagesChanged: (_) {},
            onInterestsChanged: (_) {},
            onNext: () {},
            onSkip: () {},
            isSaving: false,
          ),
        ),
      ),
    );
    BoxDecoration chip(String label) =>
        tester
                .widget<Container>(
                  find
                      .ancestor(
                        of: find.text(label),
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;
    TextStyle text(String label) =>
        tester.widget<Text>(find.text(label)).style!;

    // Unselected languages and interests: same dark chip, thin grey border,
    // white text.
    for (final label in [
      profileLanguageOptions[1],
      profileInterestOptions.last,
    ]) {
      expect(chip(label).color, TravibeChoiceChip.fill);
      expect(
        (chip(label).border! as Border).top,
        const BorderSide(color: TravibeChoiceChip.border),
      );
      expect(text(label).color, Colors.white);
      expect(text(label).fontSize, 14);
    }
    // Selected stays orange with white semibold text.
    for (final label in ['English', 'Hiking']) {
      expect(chip(label).color, DarkColors.primaryColor);
      expect(text(label).color, Colors.white);
      expect(text(label).fontWeight, FontWeight.w600);
    }
    // Figma chip height: 8 + 20 + 8 + 2px border.
    expect(
      tester
          .getSize(
            find
                .ancestor(
                  of: find.text('English'),
                  matching: find.byType(Container),
                )
                .first,
          )
          .height,
      38,
    );
    expect(find.text('Add Another'), findsNothing);
    expect(showAddAnotherLanguage, false);

    final interests = tester.getRect(
      find.ancestor(
        of: find.text(profileInterestOptions.last),
        matching: find.byType(Wrap),
      ),
    );
    final next = tester.getRect(find.byType(CustomButton));
    expect(next.top - interests.bottom, 40);
    final skip = find.widgetWithText(TextButton, 'Skip For Now');
    expect(tester.getRect(skip).top - next.bottom, 16);
    expect(
      tester.widget<TextButton>(skip).style!.foregroundColor!.resolve({}),
      DarkColors.primaryColor,
    );
  });

  testWidgets('step indicator: equal bars, done and current orange', (
    tester,
  ) async {
    Future<List<Color?>> bars(int current) async {
      await tester.pumpWidget(
        MaterialApp(home: SetupStepIndicator(count: 3, current: current)),
      );
      await tester.pumpAndSettle();
      return [
        for (var i = 0; i < 3; i++)
          (tester
                      .widget<AnimatedContainer>(
                        find.byKey(ValueKey('setup-step-bar-$i')),
                      )
                      .decoration!
                  as BoxDecoration)
              .color,
      ];
    }

    const orange = DarkColors.primaryColor;
    const grey = SetupStepIndicator.upcomingColor;
    expect(await bars(0), [orange, grey, grey]);
    expect(await bars(1), [orange, orange, grey]);
    expect(await bars(2), [orange, orange, orange]);
    for (var i = 0; i < 3; i++) {
      expect(
        tester.getSize(find.byKey(ValueKey('setup-step-bar-$i'))),
        const Size(44, 6),
      );
    }
  });
}
