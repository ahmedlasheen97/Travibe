import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/buddies/data/buddies_repo.dart';
import 'package:travibe/features/buddies/screens/buddies_screen.dart';
import 'package:travibe/features/buddies/widgets/buddies_complete_profile_card.dart';
import 'package:travibe/features/buddies/widgets/buddies_visibility_invitation.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/data/profile_repo.dart';
import 'package:travibe/features/profile/data/settings_repo.dart';
import 'package:travibe/features/profilesetup/cubit/profile_setup_cubit.dart';
import 'package:travibe/features/profilesetup/data/profile_setup_repo.dart';
import 'package:travibe/features/profilesetup/screens/profile_setup_screen.dart';
import 'buddies_backend_integration_test.dart' show LocationApi, cairo;
import 'buddies_home_test.dart' as home;

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
    api = LocationApi()..profile['profile_completed'] = false;
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

  Future<void> showBuddies(WidgetTester tester, home.FakeApi buddies) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: BlocProvider.value(
            value: user,
            child: BuddiesScreen(repo: BuddiesRepo(apiService: buddies)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Complete Profile card disappears as soon as setup completes and a city is saved',
    (tester) async {
      final buddies = home.FakeApi(home.home(complete: false, visible: false));
      await showBuddies(tester, buddies);
      expect(find.byType(BuddiesCompleteProfileCard), findsOneWidget);
      expect(find.byType(BuddiesVisibilityInvitation), findsOneWidget);

      // The server confirms completion; the home meta still says false.
      api.profile['profile_completed'] = true;
      await user.load();
      await tester.pumpAndSettle();
      // Still no current city, so the card stays.
      expect(find.byType(BuddiesCompleteProfileCard), findsOneWidget);

      await user.saveLocation(cairo());
      await tester.pumpAndSettle();
      expect(find.byType(BuddiesCompleteProfileCard), findsNothing);
      // Visibility is still off, so its card remains on its own.
      expect(find.byType(BuddiesVisibilityInvitation), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Complete Profile opens setup at the first missing step', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Identity and city are done; languages/interests are still missing.
    api.profile['username'] = 'account';
    await user.saveLocation(cairo());
    await user.load();
    expect(user.state.profile!.currentLocation, 'Cairo, EG');
    final buddies = home.FakeApi(home.home(complete: false, city: true));
    await showBuddies(tester, buddies);
    await tester.tap(find.text('Complete Profile'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final screen = tester.widget<ProfileSetupScreen>(
      find.byType(ProfileSetupScreen),
    );
    expect(screen.initialStep, 1);
    expect(screen.popOnComplete, true);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Profile Setup keeps the Current City picker but has no Buddies switch',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final cubit = ProfileSetupCubit(
        currentUser: user,
        repo: ProfileSetupRepo(apiService: api),
        profileRepo: ProfileRepo(apiService: api),
      );
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            theme: darkTheme,
            home: BlocProvider.value(
              value: user,
              child: ProfileSetupScreen(createCubit: (_) => cubit),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final city = find.text('Select your current city');
      await tester.dragUntilVisible(
        city,
        find.byType(ListView).first,
        const Offset(0, -200),
      );
      expect(find.text('Current City'), findsOneWidget);
      expect(city, findsOneWidget);
      expect(find.text('Show me in Buddies'), findsNothing);
      expect(
        find.text('Let travelers in your city discover you.'),
        findsNothing,
      );
      expect(find.byType(Switch), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('Buddies artwork ships as 1x/2x/3x PNG', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    for (final name in ['completeprofile', 'visibility']) {
      final asset = 'assets/images/buddies/$name.png';
      final variants = manifest
          .getAssetVariants(asset)!
          .map((variant) => variant.targetDevicePixelRatio ?? 1.0)
          .toSet();
      expect(variants, {1.0, 2.0, 3.0}, reason: asset);
    }
  });
}
