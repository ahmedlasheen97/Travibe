import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:travibe/core/location/device_location_service.dart';

class Platform extends GeolocatorPlatform {
  bool enabled = true;
  LocationPermission permission = LocationPermission.denied;
  LocationPermission requested = LocationPermission.whileInUse;
  Object? error;
  final calls = <String>[];
  LocationSettings? settings;
  @override
  Future<bool> isLocationServiceEnabled() async => enabled;
  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async {
    calls.add('permission');
    return requested;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    calls.add('position');
    settings = locationSettings;
    if (error != null) throw error!;
    return Position(
      longitude: 31.23,
      latitude: 30.04,
      timestamp: DateTime(2026),
      accuracy: 100,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }

  @override
  Future<bool> openAppSettings() async {
    calls.add('app-settings');
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    calls.add('location-settings');
    return true;
  }
}

void main() {
  late GeolocatorPlatform original;
  late Platform platform;
  final service = GeolocatorDeviceLocationService();
  setUp(() {
    original = GeolocatorPlatform.instance;
    platform = Platform();
    GeolocatorPlatform.instance = platform;
  });
  tearDown(() => GeolocatorPlatform.instance = original);
  test(
    'permission is requested once and one-shot location has a 15-second deadline',
    () async {
      final coordinates = await service.locate();
      expect(platform.calls, ['permission', 'position']);
      expect(coordinates.latitude, 30.04);
      expect(coordinates.longitude, 31.23);
      expect(platform.settings!.timeLimit, const Duration(seconds: 15));
    },
  );
  test('already granted does not reprompt', () async {
    platform.permission = LocationPermission.whileInUse;
    await service.locate();
    expect(platform.calls, ['position']);
  });
  test('denial provides manual selection and does not read position', () async {
    platform.requested = LocationPermission.denied;
    await expectLater(
      service.locate(),
      throwsA(
        isA<DeviceLocationException>().having(
          (e) => e.message,
          'manual',
          'Location permission was not granted. You can still choose a destination manually.',
        ),
      ),
    );
    expect(platform.calls, ['permission']);
  });
  test(
    'permanent denial does not repeatedly prompt and offers settings',
    () async {
      platform.permission = LocationPermission.deniedForever;
      await expectLater(
        service.locate(),
        throwsA(
          isA<DeviceLocationException>().having(
            (e) => e.openSettings,
            'settings',
            true,
          ),
        ),
      );
      expect(platform.calls, isEmpty);
      await service.openSettings();
      expect(platform.calls, ['app-settings']);
    },
  );
  test('disabled services never prompt permission', () async {
    platform.enabled = false;
    await expectLater(
      service.locate(),
      throwsA(isA<DeviceLocationException>()),
    );
    expect(platform.calls, isEmpty);
    await service.openSettings();
    expect(platform.calls, ['location-settings']);
  });
  test('device timeout is actionable', () async {
    platform.error = TimeoutException('test');
    await expectLater(
      service.locate(),
      throwsA(
        isA<DeviceLocationException>().having(
          (e) => e.message,
          'timeout',
          contains('timed out'),
        ),
      ),
    );
  });
}
