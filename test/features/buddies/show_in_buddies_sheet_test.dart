import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/location/device_location_service.dart';
import 'package:travibe/core/places/city_places_provider.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/buddies/cubit/allow_location_cubit.dart';
import 'package:travibe/features/buddies/widgets/buddies_visibility_invitation.dart';
import 'package:travibe/features/buddies/widgets/show_in_buddies_sheet.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/data/profile_repo.dart';
import 'package:travibe/features/profile/data/settings_repo.dart';
import 'package:travibe/features/profile/data/settings_update.dart';
import 'package:travibe/features/profile/screens/settings_screen.dart';
import 'buddies_backend_integration_test.dart' show LocationApi, cairo;

/// Exact device fix; only a ~1 km rounded copy may leave the device.
class PreciseDevice implements DeviceLocationService {
  PreciseDevice(this.events);
  final List<String> events;
  Object? failure;
  int settingsOpened = 0;
  @override
  Future<DeviceCoordinates> locate() async {
    events.add('device');
    if (failure != null) throw failure!;
    return const DeviceCoordinates(30.044419, 31.235712);
  }

  @override
  Future<void> openSettings() async => settingsOpened++;
}

class RecordingReverse implements CityReverseGeocoder {
  RecordingReverse(this.events);
  final List<String> events;
  double? latitude, longitude;
  @override
  Future<CitySelection> reverse(double latitude, double longitude) async {
    events.add('reverse');
    this.latitude = latitude;
    this.longitude = longitude;
    return cairo();
  }
}

void main() {
  final preferences = PreferencesManager();
  late LocationApi api;
  late CurrentUserCubit user;
  late PreciseDevice device;
  late RecordingReverse reverse;
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
    device = PreciseDevice(api.calls);
    reverse = RecordingReverse(api.calls);
    picked = cairo();
  });
  tearDown(() async {
    await user.close();
    await preferences.clear();
  });

  Future<void> openSheet(WidgetTester tester) async {
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
                  device: device,
                  geocoder: reverse,
                  pickCity: (_) async {
                    api.calls.add('picker');
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

  test('coordinates are coarsened to 2 decimals', () {
    expect(coarseCoordinate(30.044419), 30.04);
    expect(coarseCoordinate(-0.125), -0.13);
    expect(coarseCoordinate(31.235712), 31.24);
  });

  testWidgets('no city: Figma copy with Use my location and manual choice', (
    tester,
  ) async {
    await openSheet(tester);
    expect(find.text('Show me in Buddies'), findsOneWidget);
    expect(
      find.text(
        'Allow Travibe to use your current location to show you to people nearby.',
      ),
      findsOneWidget,
    );
    expect(
      find.text("We'll show your city, not your exact location."),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.location_on_rounded), findsOneWidget);
    expect(find.text('Use my location'), findsOneWidget);
    expect(find.text('Choose city manually'), findsOneWidget);
    expect(find.text('Change city'), findsNothing);
    expect(find.text('Not Now'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Use my location saves only the city, turns on Show in Buddies, closes and toasts',
    (tester) async {
      await openSheet(tester);
      await tester.tap(find.text('Use my location'));
      await tester.pumpAndSettle();
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
      // The exact fix never leaves the device, even to the geocoder.
      expect(reverse.latitude, 30.04);
      expect(reverse.longitude, 31.24);
      for (final payload in api.payloads) {
        expect(payload.keys, isNot(contains('latitude')));
        expect(payload.keys, isNot(contains('longitude')));
      }
      expect(user.state.profile!.showInTravelBuddy, true);
      expect(find.byType(ShowInBuddiesSheet), findsNothing);
      expect(find.text(showInBuddiesSuccessMessage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('denied permission shows the message and saves nothing', (
    tester,
  ) async {
    device.failure = const DeviceLocationException(
      'Location permission was not granted.',
    );
    await openSheet(tester);
    await tester.tap(find.text('Use my location'));
    await tester.pumpAndSettle();
    expect(find.text('Location permission was not granted.'), findsOneWidget);
    expect(find.text('Open Settings'), findsNothing);
    expect(api.calls, ['device']);
    expect(find.byType(ShowInBuddiesSheet), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('permanently denied offers Open Settings', (tester) async {
    device.failure = const DeviceLocationException(
      'Location permission is disabled.',
      openSettings: true,
    );
    await openSheet(tester);
    await tester.tap(find.text('Use my location'));
    await tester.pumpAndSettle();
    expect(find.text('Location permission is disabled.'), findsOneWidget);
    await tester.tap(find.text('Open Settings'));
    await tester.pump();
    expect(device.settingsOpened, 1);
    expect(user.state.profile!.showInTravelBuddy, false);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Not Now closes without any request', (tester) async {
    await openSheet(tester);
    await tester.tap(find.text('Not Now'));
    await tester.pumpAndSettle();
    expect(find.byType(ShowInBuddiesSheet), findsNothing);
    expect(api.calls, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no city: Choose city manually saves the pick then turns on', (
    tester,
  ) async {
    await openSheet(tester);
    await tester.tap(find.text('Choose city manually'));
    await tester.pumpAndSettle();
    expect(api.calls, ['picker', 'PUT profile/location', 'PATCH settings']);
    expect(api.payloads, [
      {'location': 'Cairo, EG'},
      {'show_in_travel_buddy': true},
    ]);
    expect(find.byType(ShowInBuddiesSheet), findsNothing);
    expect(find.text(showInBuddiesSuccessMessage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no city: dismissing the picker changes nothing', (tester) async {
    picked = null;
    await openSheet(tester);
    await tester.tap(find.text('Choose city manually'));
    await tester.pumpAndSettle();
    expect(api.calls, ['picker']);
    expect(find.byType(ShowInBuddiesSheet), findsOneWidget);
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
      expect(find.text('Turn On'), findsOneWidget);
      expect(find.text('Change city'), findsOneWidget);
      expect(find.text('Use my location'), findsNothing);
      expect(find.text('Choose city manually'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Turn On only PATCHes show_in_travel_buddy', (tester) async {
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
    });

    testWidgets('Change city picks, saves, then turns on', (tester) async {
      picked = CitySelection(
        cityName: 'Alexandria',
        countryName: 'Egypt',
        countryCode: 'EG',
        latitude: 31.2,
        longitude: 29.92,
      );
      await openSheet(tester);
      await tester.tap(find.text('Change city'));
      await tester.pumpAndSettle();
      expect(api.calls, ['picker', 'PUT profile/location', 'PATCH settings']);
      expect(api.payloads.first, {'location': 'Alexandria, EG'});
      expect(user.state.profile!.currentLocation, 'Alexandria, EG');
      expect(user.state.profile!.showInTravelBuddy, true);
      await tester.pumpWidget(const SizedBox());
    });

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
