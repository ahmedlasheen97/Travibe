import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/profilesetup/data/reference_item.dart';
import 'package:travibe/features/profilesetup/data/profile_setup_repo.dart';
import 'package:travibe/features/profilesetup/data/profile_setup_result.dart';
import 'package:travibe/features/profilesetup/cubit/profile_setup_cubit.dart';
import 'package:travibe/features/profilesetup/widgets/step3_travel_style.dart';
import 'package:travibe/features/buddies/screens/buddies_filters_screen.dart';
import 'package:travibe/features/buddies/data/buddies_filters.dart';
import 'profile_setup_test.dart' as fixtures;

const liveBrokenCatalog = {
  'data': {'__PHP_Incomplete_Class_Name': 'Illuminate\\Support\\Collection'},
};

Map<String, dynamic> setupResponse({
  String step = 'review',
  bool completed = false,
  Map<String, dynamic> user = const {'id': 7},
}) => {
  'data': user,
  'meta': {'profile_completed': completed, 'profile_setup_step': step},
};

class SetupApi extends fixtures.FakeApi {
  dynamic result = setupResponse();
  dynamic completion = setupResponse(step: 'complete', completed: true);
  Completer<dynamic>? pending;
  @override
  Future<dynamic> patch(String endpoint, Map<String, dynamic> data) async {
    expect(endpoint, 'profile/setup');
    patches.add(data);
    if (pending != null) return pending!.future;
    if (result is ApiError) throw result as ApiError;
    return result;
  }

  @override
  Future<dynamic> post(String endpoint, Map<String, dynamic> data) async {
    posts.add(endpoint);
    if (completion is ApiError) throw completion as ApiError;
    return completion;
  }
}

class CatalogApi extends ApiService {
  dynamic response;
  final gets = <String>[];
  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
    gets.add(endpoint);
    if (response is ApiError) throw response as ApiError;
    return response;
  }
}

void main() {
  test(
    'live PHP incomplete Collection is rejected without inventing or emptying options',
    () {
      expect(
        () => ReferenceItem.parseCatalog(liveBrokenCatalog),
        throwsA(
          isA<ApiError>().having(
            (error) => error.message,
            'message',
            ReferenceItem.unavailableMessage,
          ),
        ),
      );
    },
  );

  for (final kind in ReferenceKind.values) {
    test(
      '${kind.path} uses the actual reference endpoint and parses the documented item shape',
      () async {
        final api = CatalogApi()
          ..response = {
            'data': [
              fixtures.item(
                'verified-slug',
                'Returned name',
                status: kind == ReferenceKind.languages ? 'active' : null,
              ),
            ],
          };
        final result = await ProfileSetupRepo(
          apiService: api,
        ).loadCatalog(kind);
        expect(api.gets, ['reference/${kind.path}']);
        expect(result.single.slug, 'verified-slug');
        expect(result.single.nameEn, 'Returned name');
        expect(result.single.nameAr, 'اسم Returned name');
        expect(() => result.clear(), throwsUnsupportedError);
        api.response = liveBrokenCatalog;
        await expectLater(
          ProfileSetupRepo(apiService: api).loadCatalog(kind),
          throwsA(
            isA<ApiError>().having(
              (error) => error.message,
              'message',
              ReferenceItem.unavailableMessage,
            ),
          ),
        );
      },
    );
  }

  test(
    'malformed catalogs, duplicate slugs and transport errors remain failures',
    () async {
      for (final json in [
        null,
        [],
        {'data': {}},
        {
          'data': [
            {'slug': 'a', 'name': 'A'},
          ],
        },
        {
          'data': [fixtures.item('a', 'A'), fixtures.item('a', 'A')],
        },
      ]) {
        expect(
          () => ReferenceItem.parseCatalog(json),
          throwsA(isA<ApiError>()),
        );
      }
      final error = ApiError(message: 'Access denied', statusCode: 403);
      final api = CatalogApi()..response = error;
      await expectLater(
        ProfileSetupRepo(
          apiService: api,
        ).loadCatalog(ReferenceKind.travelStyles),
        throwsA(same(error)),
      );
    },
  );

  test('PATCH parses UserResource and every verified setup step', () async {
    final api = SetupApi();
    final repo = ProfileSetupRepo(apiService: api);
    for (final step in ProfileSetupStep.values) {
      api.result = setupResponse(
        step: step.value,
        completed: step == ProfileSetupStep.complete,
        user: {
          'id': 7,
          'username': 'sara',
          'travel_styles': [
            {'slug': 'saved_style', 'name': 'Saved style'},
          ],
        },
      );
      final result = await repo.saveSetup(username: 'sara', gender: 'other');
      expect(result.step, step);
      expect(result.profileCompleted, step == ProfileSetupStep.complete);
      expect(result.profile!.id, '7');
      expect(result.profile!.travelStyleSelections.single.slug, 'saved_style');
      expect(api.patches.last, {'username': 'sara', 'gender': 'other'});
    }
  });

  test('malformed PATCH metadata/resources cannot report success', () async {
    final api = SetupApi();
    final repo = ProfileSetupRepo(apiService: api);
    for (final response in [
      {
        'data': {'id': 7},
      },
      setupResponse(step: 'invented'),
      {
        'data': {'id': 7},
        'meta': {'profile_completed': 'false', 'profile_setup_step': 'review'},
      },
      setupResponse(user: {}),
      {
        'data': [],
        'meta': {'profile_completed': true, 'profile_setup_step': 'complete'},
      },
    ]) {
      api.result = response;
      await expectLater(
        repo.saveSetup(fullName: 'Sara'),
        throwsA(isA<ApiError>()),
      );
    }
  });

  test('username and gender validation stops invalid PATCH requests', () async {
    final api = SetupApi();
    final repo = ProfileSetupRepo(apiService: api);
    for (final username in ['ab', 'a' * 31]) {
      await expectLater(
        repo.saveSetup(username: username),
        throwsA(isA<ApiError>()),
      );
    }
    await expectLater(
      repo.saveSetup(gender: 'invented'),
      throwsA(isA<ApiError>()),
    );
    expect(api.patches, isEmpty);
    for (final gender in ['male', 'female', 'other']) {
      await repo.saveSetup(gender: gender);
      expect(api.patches.last, {'gender': gender});
    }
  });

  test(
    'PATCH can explicitly clear travel styles without fetching an unavailable catalog',
    () async {
      final api = SetupApi()..failedCatalog = 'travel-styles';
      await ProfileSetupRepo(apiService: api).saveSetup(travelStyles: []);
      expect(api.patches.single, {'travel_styles': []});
      expect(api.gets, isEmpty);
    },
  );

  test(
    'canonical previously saved selections survive partial saves and catalog failure',
    () async {
      final api = SetupApi()
        ..result = setupResponse(
          user: {
            'id': 7,
            'languages_spoken': [
              {'slug': 'returned_language', 'name': 'Returned language'},
            ],
            'interests': [
              {'slug': 'returned_interest', 'name': 'Returned interest'},
            ],
            'travel_styles': [
              {'slug': 'returned_style', 'name': 'Returned style'},
            ],
          },
        );
      final repo = ProfileSetupRepo(apiService: api);
      final cubit = ProfileSetupCubit(repo: repo);
      addTearDown(cubit.close);
      cubit.fullNameController.text = 'Sara';
      cubit.usernameController.text = 'sara';
      await cubit.saveBasicInfo();
      expect(cubit.state.languages, ['returned_language']);
      expect(cubit.state.interests, ['returned_interest']);
      expect(cubit.state.travelStyles, ['returned_style']);
      api.failedCatalog = 'travel-styles';
      await cubit.loadCatalogs();
      expect(cubit.state.travelStyles, ['returned_style']);
      api.result = setupResponse(step: 'travel_style', user: {'id': 7});
      await cubit.saveLanguagesAndInterests();
      expect(api.patches.last, {
        'languages_spoken': ['returned_language'],
        'interests': ['returned_interest'],
      });
      await cubit.finish();
      expect(api.patches.last, {
        'travel_styles': ['returned_style'],
      });
      expect(cubit.state.travelStyles, ['returned_style']);
      expect(cubit.state.profileCompleted, false);
      expect(cubit.state.step, 2);
      expect(api.posts, isEmpty);
    },
  );

  test(
    'catalog refresh does not silently remove selected styles and three-selection limit stays enforced',
    () async {
      final api = SetupApi();
      final cubit = ProfileSetupCubit(repo: ProfileSetupRepo(apiService: api));
      addTearDown(cubit.close);
      await cubit.loadCatalogs();
      cubit.setTravelStyles([
        'solo_traveler',
        'group_traveler',
        'couple_escapes',
      ]);
      cubit.setTravelStyles([
        'solo_traveler',
        'group_traveler',
        'couple_escapes',
        'family_traveler',
      ]);
      expect(cubit.state.travelStyles, hasLength(3));
      api.catalogs['travel-styles'] = [];
      await cubit.loadCatalogs();
      expect(cubit.state.travelStyles, hasLength(3));
      cubit.setTravelStyles(['solo_traveler', 'group_traveler']);
      expect(cubit.state.travelStyles, hasLength(2));
      cubit.setTravelStyles(['invented']);
      expect(cubit.state.travelStyles, hasLength(2));
    },
  );

  for (final step in [
    ProfileSetupStep.identity,
    ProfileSetupStep.languagesInterests,
    ProfileSetupStep.travelStyle,
  ]) {
    test(
      'finish follows server ${step.value} without pretending completion',
      () async {
        final api = SetupApi()..result = setupResponse(step: step.value);
        final cubit = ProfileSetupCubit(
          repo: ProfileSetupRepo(apiService: api),
        );
        addTearDown(cubit.close);
        await cubit.finish();
        expect(cubit.state.serverStep, step);
        expect(cubit.state.step, step.page);
        expect(cubit.state.profileCompleted, false);
        expect(cubit.state.status, ProfileSetupStatus.editing);
        expect(api.posts, isEmpty);
      },
    );
  }

  test(
    'server review authorizes the existing completion call even without local identity edits',
    () async {
      final api = SetupApi();
      final cubit = ProfileSetupCubit(repo: ProfileSetupRepo(apiService: api));
      addTearDown(cubit.close);
      await cubit.finish();
      expect(api.patches.single, {'travel_styles': []});
      expect(api.posts, ['profile/setup/complete']);
      expect(cubit.state.status, ProfileSetupStatus.completed);
      expect(cubit.state.profileCompleted, true);
    },
  );

  test('PATCH completed true skips a redundant completion call', () async {
    final api = SetupApi()
      ..result = setupResponse(step: 'complete', completed: true);
    final cubit = ProfileSetupCubit(repo: ProfileSetupRepo(apiService: api));
    addTearDown(cubit.close);
    await cubit.finish();
    expect(api.posts, isEmpty);
    expect(cubit.state.status, ProfileSetupStatus.completed);
  });

  test(
    'completion false and completion failures never navigate Home or lose selections',
    () async {
      final api = SetupApi()
        ..completion = setupResponse(step: 'complete', completed: false);
      final cubit = ProfileSetupCubit(repo: ProfileSetupRepo(apiService: api));
      addTearDown(cubit.close);
      await cubit.loadCatalogs();
      cubit.setTravelStyles(['solo_traveler']);
      await cubit.finish();
      expect(cubit.state.status, ProfileSetupStatus.failure);
      expect(cubit.state.profileCompleted, false);
      expect(cubit.state.travelStyles, ['solo_traveler']);
      api.completion = ApiError(message: 'Missing identity', statusCode: 422);
      await cubit.finish();
      expect(cubit.state.status, ProfileSetupStatus.failure);
      expect(cubit.state.errorMessage, 'Missing identity');
      expect(cubit.state.travelStyles, ['solo_traveler']);
    },
  );

  test(
    'duplicate saves and disposal cannot publish a late completion',
    () async {
      final pending = Completer<dynamic>();
      final api = SetupApi()..pending = pending;
      final cubit = ProfileSetupCubit(repo: ProfileSetupRepo(apiService: api));
      final first = cubit.finish();
      await cubit.finish();
      expect(api.patches, hasLength(1));
      await cubit.close();
      pending.complete(setupResponse(step: 'complete', completed: true));
      await first;
      expect(cubit.state.status, isNot(ProfileSetupStatus.completed));
      expect(api.posts, isEmpty);
    },
  );

  testWidgets('username over 30 characters is not checked remotely', (
    tester,
  ) async {
    final api = SetupApi();
    final cubit = ProfileSetupCubit(repo: ProfileSetupRepo(apiService: api));
    cubit.onUsernameChanged('a' * 31);
    await tester.pump(const Duration(milliseconds: 501));
    expect(cubit.state.usernameStatus, UsernameStatus.invalid);
    expect(api.gets, isEmpty);
    await cubit.close();
  });

  testWidgets(
    'all eight original travel-style cards keep order, artwork and selection limit',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const labels = [
        'Solo Traveler',
        'Group Traveler',
        'Couple Escapes',
        'Family Traveler',
        'Backpacker',
        'Adventure Seeker',
        'Leisure Traveler',
        'Digital Nomad',
      ];
      final items = [
        for (var i = 0; i < labels.length; i++)
          ReferenceItem(
            slug: 'fixture-style-$i',
            name: labels[i],
            nameEn: labels[i],
            nameAr: labels[i],
          ),
      ];
      var selected = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Step3TravelStyle(
                selectedTravelStyles: selected,
                onTravelStylesChanged: (value) =>
                    setState(() => selected = value),
                onFinish: () {},
                isSubmitting: false,
                catalog: ReferenceCatalog(
                  status: CatalogStatus.loaded,
                  items: items.reversed.toList(),
                ),
                onRetry: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNWidgets(8));
      for (final label in labels) {
        expect(find.text(label), findsOneWidget);
      }
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text(labels[i]));
        await tester.pump();
      }
      expect(selected, [
        'fixture-style-0',
        'fixture-style-1',
        'fixture-style-2',
      ]);
      expect(find.text('You can select up to 3 travel styles'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(labels[0])).dx,
        lessThan(tester.getTopLeft(find.text(labels[1])).dx),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Buddies uses the same parser and exposes the live catalog failure with retry',
    (tester) async {
      final api = CatalogApi()..response = liveBrokenCatalog;
      await tester.pumpWidget(
        MaterialApp(
          home: BuddiesFiltersScreen(
            initial: BuddiesFilters(),
            catalogRepo: ProfileSetupRepo(apiService: api),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.gets.toSet(), {
        'reference/languages',
        'reference/interests',
        'reference/travel-styles',
      });
      await tester.scrollUntilVisible(find.text('Retry Travel Style'), 160);
      await tester.pumpAndSettle();
      expect(find.text(ReferenceItem.unavailableMessage), findsWidgets);
      expect(find.text('Invalid reference catalog response.'), findsNothing);
      await tester.tap(find.text('Retry Travel Style'));
      await tester.pumpAndSettle();
      expect(
        api.gets.where((path) => path == 'reference/travel-styles'),
        hasLength(2),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
