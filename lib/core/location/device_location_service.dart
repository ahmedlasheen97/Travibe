import 'dart:async';
import 'package:geolocator/geolocator.dart';

class DeviceCoordinates {
  const DeviceCoordinates(this.latitude, this.longitude);
  final double latitude, longitude;
}

class DeviceLocationException implements Exception {
  const DeviceLocationException(this.message, {this.openSettings = false});
  final String message;
  final bool openSettings;
}

abstract interface class DeviceLocationService {
  Future<DeviceCoordinates> locate();
  Future<void> openSettings();
}

/// Foreground, one-shot permission request, invoked only by an explicit action.
class GeolocatorDeviceLocationService implements DeviceLocationService {
  @override
  Future<DeviceCoordinates> locate() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const DeviceLocationException(
        'Location services are off. Enable them in Settings, or choose a city manually.',
        openSettings: true,
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const DeviceLocationException(
        'Location permission is disabled. Open Settings to allow access, or choose a city manually.',
        openSettings: true,
      );
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      throw const DeviceLocationException(
        'Location permission was not granted. You can still choose a destination manually.',
      );
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return DeviceCoordinates(position.latitude, position.longitude);
    } on TimeoutException {
      throw const DeviceLocationException(
        'Finding your location timed out. Try again, or choose a city manually.',
      );
    }
  }

  @override
  Future<void> openSettings() async {
    if (await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openAppSettings();
    } else {
      await Geolocator.openLocationSettings();
    }
  }
}
