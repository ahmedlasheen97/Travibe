import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'package:travibe/features/profile/data/profile_repo.dart';
import 'package:travibe/features/profilesetup/cubit/profile_setup_cubit.dart';
import 'package:travibe/features/profilesetup/data/profile_setup_repo.dart';
import 'package:travibe/features/profilesetup/screens/profile_setup_screen.dart';
import 'package:travibe/features/profilesetup/widgets/step2_languages_interests.dart';
import 'identity_photo_test.dart' show SetupApi, Photos, Upload;

const _ref = ProfileReference(slug: 'x', name: 'X');

/// SetupApi echoes selections as plain slugs; the real API returns
/// `{slug, name}` objects, which ProfileModel requires.
class SkipApi extends SetupApi {
  /// The server confirms completion on the travel-style PATCH.
  bool completeOnTravelStyles = false;

  @override
  Future<dynamic> patch(String endpoint, Map<String, dynamic> data) async {
    final response = await super.patch(endpoint, data);
    if (completeOnTravelStyles && data.containsKey('travel_styles')) {
      (response['meta'] as Map)['profile_completed'] = true;
      (response['meta'] as Map)['profile_setup_step'] = 'complete';
    }
    for (final key in ['languages_spoken', 'interests', 'travel_styles']) {
      final value = profile[key];
      if (value is List && value.every((item) => item is String)) {
        final objects = [
          for (final slug in value) {'slug': slug, 'name': slug},
        ];
        profile[key] = objects;
        (response['data'] as Map)[key] = objects;
      }
    }
    return response;
  }
}

void main() {
  final preferences = PreferencesManager();
  late SkipApi api;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.saveToken('setup-skip');
    ScreenUtil.configure(
      data: const MediaQueryData(size: Size(390, 844)),
      designSize: const Size(390, 844),
      minTextAdapt: false,
      splitScreenMode: false,
    );
    api = SkipApi();
  });
  tearDown(() => preferences.clear());

  ProfileSetupCubit make({int initialStep = 0}) {
    final upload = Upload();
    final cubit = ProfileSetupCubit(
      repo: ProfileSetupRepo(apiService: api),
      profileRepo: ProfileRepo(apiService: api),
      avatarRepo: Photos(),
      mediaUpload: upload,
      initialStep: initialStep,
    );
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
      upload.close();
    });
    return cubit;
  }

  group('firstMissingStep', () {
    ProfileModel profile({
      String? location = 'Cairo, EG',
      bool languages = true,
      bool interests = true,
      bool styles = true,
    }) => ProfileModel(
      id: '7',
      name: 'Alice',
      username: 'alice',
      currentLocation: location,
      languageSelections: languages ? const [_ref] : const [],
      interestSelections: interests ? const [_ref] : const [],
      travelStyleSelections: styles ? const [_ref] : const [],
    );

    test('city first, then languages/interests, then travel style', () {
      expect(ProfileSetupCubit.firstMissingStep(null), 0);
      expect(
        ProfileSetupCubit.firstMissingStep(
          profile(location: null, languages: false, styles: false),
        ),
        0,
      );
      expect(ProfileSetupCubit.firstMissingStep(profile(languages: false)), 1);
      expect(ProfileSetupCubit.firstMissingStep(profile(interests: false)), 1);
      expect(ProfileSetupCubit.firstMissingStep(profile(styles: false)), 2);
      expect(ProfileSetupCubit.firstMissingStep(profile()), 0);
    });

    test('a missing name or username means identity', () {
      expect(
        ProfileSetupCubit.firstMissingStep(
          const ProfileModel(id: '7', currentLocation: 'Cairo, EG'),
        ),
        0,
      );
    });
  });

  test(
    'Skip on step 2 saves entered selections and remembers the skip',
    () async {
      final cubit = make(initialStep: 1);
      await cubit.restore();
      cubit.setLanguages(['English']);
      await cubit.skip();
      expect(api.patches.single, {
        'languages_spoken': ['english'],
      });
      expect(cubit.state.status, ProfileSetupStatus.skipped);
      expect(preferences.isProfileSetupSkipped('7'), true);
    },
  );

  test('Skip with nothing entered sends nothing and still skips', () async {
    final cubit = make(initialStep: 2);
    await cubit.restore();
    await cubit.skip();
    expect(api.patches, isEmpty);
    expect(cubit.state.status, ProfileSetupStatus.skipped);
    expect(preferences.isProfileSetupSkipped('7'), true);
  });

  test('a failed save keeps the user in setup and does not skip', () async {
    final cubit = make(initialStep: 1);
    await cubit.restore();
    cubit.setLanguages(['English']);
    api.patchError = ApiError(message: 'Offline');
    await cubit.skip();
    expect(cubit.state.status, ProfileSetupStatus.failure);
    expect(preferences.isProfileSetupSkipped('7'), false);
  });

  testWidgets(
    'opened from Buddies: starts at the given step, has Back, Skip returns',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final cubit = make(initialStep: 1);
      Object? popped = 'not popped';
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            theme: darkTheme,
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  popped = await Navigator.of(context).push<Object?>(
                    MaterialPageRoute(
                      builder: (_) => ProfileSetupScreen(
                        createCubit: (_) => cubit,
                        popOnComplete: true,
                        initialStep: 1,
                      ),
                    ),
                  );
                },
                child: const Text('Complete Profile'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Complete Profile'));
      await tester.pumpAndSettle();
      expect(cubit.state.step, 1);
      expect(find.text('Languages Spoken'), findsOneWidget);
      expect(find.byTooltip('Back'), findsOneWidget);
      final skip = find.text('Skip for now');
      await tester.scrollUntilVisible(
        skip,
        200,
        scrollable: find
            .descendant(
              of: find.byType(Step2LanguagesInterests),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(skip);
      await tester.pumpAndSettle();
      expect(find.byType(ProfileSetupScreen), findsNothing);
      expect(popped, true);
      expect(preferences.isProfileSetupSkipped('7'), true);
    },
  );

  testWidgets('travel style step shows Skip for now under its button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cubit = make(initialStep: 2);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: ProfileSetupScreen(createCubit: (_) => cubit, initialStep: 2),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final finish = find.text('Continue to Home');
    final skip = find.text('Skip for now');
    expect(skip, findsOneWidget);
    expect(
      tester.getTopLeft(skip).dy,
      greaterThan(tester.getTopLeft(finish).dy),
    );
    final style = tester.widget<TextButton>(
      find.ancestor(of: skip, matching: find.byType(TextButton)),
    );
    expect(style.style!.foregroundColor!.resolve({}), const Color(0xFFBDBCBB));
    await tester.pumpWidget(const SizedBox());
  });

  for (final fromBuddies in [false, true]) {
    testWidgets(
      'step 3 button reads ${fromBuddies ? '"Done" from Buddies' : '"Continue to Home" from signup'}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final cubit = make(initialStep: 2);
        await tester.pumpWidget(
          ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, _) => MaterialApp(
              theme: darkTheme,
              home: ProfileSetupScreen(
                createCubit: (_) => cubit,
                initialStep: 2,
                popOnComplete: fromBuddies,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Done'), fromBuddies ? findsOneWidget : findsNothing);
        expect(
          find.text('Continue to Home'),
          fromBuddies ? findsNothing : findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('Done finishes setup and returns to Buddies', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    api.completeOnTravelStyles = true;
    final cubit = make(initialStep: 2);
    Object? popped = 'not popped';
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                popped = await Navigator.of(context).push<Object?>(
                  MaterialPageRoute(
                    builder: (_) => ProfileSetupScreen(
                      createCubit: (_) => cubit,
                      popOnComplete: true,
                      initialStep: 2,
                    ),
                  ),
                );
              },
              child: const Text('Complete Profile'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Complete Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileSetupScreen), findsNothing);
    expect(popped, true);
    expect(find.text('Complete Profile'), findsOneWidget);
  });
}
