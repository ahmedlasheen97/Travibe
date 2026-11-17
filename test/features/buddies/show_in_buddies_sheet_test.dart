import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/places/city_places_provider.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/buddies/widgets/buddies_visibility_invitation.dart';
import 'package:travibe/features/buddies/widgets/show_in_buddies_sheet.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/data/profile_repo.dart';
import 'package:travibe/features/profile/data/settings_repo.dart';
import 'package:travibe/features/profile/data/settings_update.dart';
import 'package:travibe/features/profile/screens/settings_screen.dart';
import 'buddies_backend_integration_test.dart' show LocationApi, cairo;

void main() {
  final preferences = PreferencesManager();
  late LocationApi api;
  late CurrentUserCubit user;
  CitySelection? picked;

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
    picked = cairo();
  });
  tearDown(() async {
    await user.close();
    await preferences.clear();
  });

  Future<void> openSheet(WidgetTester tester, {bool realPicker = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        home: BlocProvider.value(
          value: user,
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showShowInBuddiesSheet(
                  context,
                  pickCity: realPicker
                      ? null
                      : (_) async {
                          api.calls.add('city search');
                          return picked;
                        },
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  void expectOnlyTwoButtons({required bool hasCity}) {
    expect(find.text('Turn On'), hasCity ? findsOneWidget : findsNothing);
    expect(find.text('Choose City'), hasCity ? findsNothing : findsOneWidget);
    expect(find.text('Allow Location'), findsNothing);
    expect(find.text('Not Now'), findsOneWidget);
    expect(find.text('Use my location'), findsNothing);
    expect(find.text('Choose city manually'), findsNothing);
    expect(find.text('Change city'), findsNothing);
    expect(find.text('Open Settings'), findsNothing);
    expect(find.byType(ElevatedButton), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
  }

  testWidgets('no city: city copy with only Choose City and Not Now', (
    tester,
  ) async {
    await openSheet(tester);
    expect(find.text('Show me in Buddies'), findsOneWidget);
    expect(
      find.text(
        'Share your current city so travelers in your city can discover you.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('location to show'), findsNothing);
    expect(
      find.text("We'll show your city, not your exact location."),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.location_on_rounded), findsOneWidget);
    expectOnlyTwoButtons(hasCity: false);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'no city: Choose City searches a city, saves it, turns on, closes and toasts',
    (tester) async {
      await openSheet(tester);
      await tester.tap(find.text('Choose City'));
      await tester.pumpAndSettle();
      expect(api.calls, [
        'city search',
        'PUT profile/location',
        'PATCH settings',
      ]);
      expect(api.payloads, [
        {'location': 'Cairo, EG'},
        {'show_in_travel_buddy': true},
      ]);
      expect(user.state.profile!.currentLocation, 'Cairo, EG');
      expect(user.state.profile!.showInTravelBuddy, true);
      expect(find.byType(ShowInBuddiesSheet), findsNothing);
      expect(find.text(showInBuddiesSuccessMessage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('no city: closing the city search changes nothing', (
    tester,
  ) async {
    picked = null;
    await openSheet(tester);
    await tester.tap(find.text('Choose City'));
    await tester.pumpAndSettle();
    expect(api.calls, ['city search']);
    expect(user.state.profile!.showInTravelBuddy, false);
    expect(find.byType(ShowInBuddiesSheet), findsOneWidget);
    expectOnlyTwoButtons(hasCity: false);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'no city: Choose City opens the Profile Setup / Edit Profile city search',
    (tester) async {
      await openSheet(tester, realPicker: true);
      await tester.tap(find.text('Choose City'));
      await tester.pumpAndSettle();
      expect(find.text('Current City'), findsOneWidget);
      expect(find.text('Search for your current city'), findsOneWidget);
      // Dismissing the search leaves the sheet as it was.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.text('Current City'), findsNothing);
      expect(find.byType(ShowInBuddiesSheet), findsOneWidget);
      expect(api.calls, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Not Now closes without any request', (tester) async {
    await openSheet(tester);
    await tester.tap(find.text('Not Now'));
    await tester.pumpAndSettle();
    expect(find.byType(ShowInBuddiesSheet), findsNothing);
    expect(api.calls, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  group('with a saved city', () {
    setUp(() async {
      await user.saveLocation(cairo());
      api.calls.clear();
      api.payloads.clear();
    });

    testWidgets('shows the city and never asks for location', (tester) async {
      await openSheet(tester);
      expect(find.text("We'll show you in Cairo, EG"), findsOneWidget);
      expect(
        find.text("We'll show your city, not your exact location."),
        findsOneWidget,
      );
      expectOnlyTwoButtons(hasCity: true);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'Turn On uses the saved city: no search, only PATCHes show_in_travel_buddy',
      (tester) async {
        await openSheet(tester);
        await tester.tap(find.text('Turn On'));
        await tester.pumpAndSettle();
        expect(api.calls, ['PATCH settings']);
        expect(api.payloads, [
          {'show_in_travel_buddy': true},
        ]);
        expect(find.byType(ShowInBuddiesSheet), findsNothing);
        expect(find.text(showInBuddiesSuccessMessage), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('a failed PATCH keeps the sheet open with the error', (
      tester,
    ) async {
      api.settingsError = ApiError(message: 'Offline');
      await openSheet(tester);
      await tester.tap(find.text('Turn On'));
      await tester.pumpAndSettle();
      expect(find.text('Offline'), findsOneWidget);
      expect(find.text('Turn On'), findsOneWidget);
      expect(find.byType(ShowInBuddiesSheet), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('Turn On Visibility opens the sheet', (tester) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: BlocProvider.value(
            value: user,
            child: const Scaffold(body: BuddiesVisibilityInvitation()),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Turn On Visibility'));
    await tester.pumpAndSettle();
    expect(find.byType(ShowInBuddiesSheet), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Settings: turning Show Me in Buddies on opens the sheet, off patches',
    (tester) async {
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            theme: darkTheme,
            home: BlocProvider.value(
              value: user,
              child: SettingsScreen(currentUser: user),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Finder toggle() => find.descendant(
        of: find
            .ancestor(
              of: find.text('Show Me in Buddies'),
              matching: find.byType(Row),
            )
            .first,
        matching: find.byType(Switch),
      );
      await tester.ensureVisible(toggle());
      await tester.tap(toggle());
      await tester.pumpAndSettle();
      expect(find.byType(ShowInBuddiesSheet), findsOneWidget);
      expect(api.calls, isNot(contains('PATCH settings')));
      await tester.tap(find.text('Not Now'));
      await tester.pumpAndSettle();
      expect(user.state.profile!.showInTravelBuddy, false);

      // Visibility already on: switching it off patches directly.
      await user.update(SettingsUpdate({'show_in_travel_buddy': true}));
      await tester.pumpAndSettle();
      api.calls.clear();
      await tester.tap(toggle());
      await tester.pumpAndSettle();
      expect(find.byType(ShowInBuddiesSheet), findsNothing);
      expect(api.calls, ['PATCH settings']);
      expect(api.payloads.last, {'show_in_travel_buddy': false});
      await tester.pumpWidget(const SizedBox());
    },
  );
}
