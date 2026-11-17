import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geocoding/geocoding.dart' as native;
import 'city_places_provider.dart';
import 'photon_city_places_provider.dart';

/// One reverse-geocoded place from the OS geocoder.
@immutable
class DevicePlacemark {
  const DevicePlacemark({
    this.locality,
    this.subAdministrativeArea,
    this.administrativeArea,
    this.country,
    this.isoCountryCode,
  });
  final String? locality,
      subAdministrativeArea,
      administrativeArea,
      country,
      isoCountryCode;
}

/// Seam over the OS geocoder (CLGeocoder on iOS, android.location.Geocoder on
/// Android) so tests never touch the platform channel.
abstract interface class DevicePlacemarkSource {
  /// False when the OS has no geocoder (Android without Google Play services).
  Future<bool> isAvailable();
  Future<List<DevicePlacemark>> placemarks(double latitude, double longitude);
}

/// `geocoding` plugin, with results forced to English.
class NativePlacemarkSource implements DevicePlacemarkSource {
  NativePlacemarkSource();
  // Created lazily: the plugin has no web implementation.
  late final native.Geocoding _geocoding = native.Geocoding(
    locale: const Locale('en', 'US'),
  );

  @override
  Future<bool> isAvailable() => _geocoding.isPresent();

  @override
  Future<List<DevicePlacemark>> placemarks(
    double latitude,
    double longitude,
  ) async => [
    for (final place in await _geocoding.placemarkFromCoordinates(
      latitude,
      longitude,
    ))
      DevicePlacemark(
        locality: place.locality,
        subAdministrativeArea: place.subAdministrativeArea,
        administrativeArea: place.administrativeArea,
        country: place.country,
        isoCountryCode: place.isoCountryCode,
      ),
  ];
}

/// "Use my location" city lookup: the device's own geocoder first (no extra
/// third party, English names), falling back to Photon on web, on Android
/// phones without Google Play services, and when the OS lookup fails.
class DeviceCityReverseGeocoder implements CityReverseGeocoder {
  DeviceCityReverseGeocoder({
    DevicePlacemarkSource? source,
    CityReverseGeocoder? fallback,
    bool? isWeb,
  }) : _deviceSource = source,
       _fallbackGeocoder = fallback,
       _isWeb = isWeb ?? kIsWeb;
  DevicePlacemarkSource? _deviceSource;
  CityReverseGeocoder? _fallbackGeocoder;
  final bool _isWeb;

  DevicePlacemarkSource get _device => _deviceSource ??= NativePlacemarkSource();
  CityReverseGeocoder get _photon => _fallbackGeocoder ??= PhotonCityPlacesProvider();

  @override
  Future<CitySelection> reverse(double latitude, double longitude) async {
    if (_isWeb) return _photon.reverse(latitude, longitude);
    final CitySelection? city;
    try {
      if (!await _device.isAvailable()) {
        return _photon.reverse(latitude, longitude);
      }
      city = _pick(
        await _device.placemarks(latitude, longitude),
        latitude,
        longitude,
      );
    } catch (_) {
      // Platform errors (no network for the OS service, throttling, missing
      // backend) are not the user's fault: try Photon instead.
      return _photon.reverse(latitude, longitude);
    }
    return city ?? _photon.reverse(latitude, longitude);
  }

  static CitySelection? _pick(
    List<DevicePlacemark> places,
    double latitude,
    double longitude,
  ) {
    for (final place in places) {
      final name = [place.locality, place.subAdministrativeArea]
          .map((value) => value?.trim())
          .firstWhere(
            (value) => value != null && value.isNotEmpty,
            orElse: () => null,
          );
      final code = place.isoCountryCode?.trim().toUpperCase();
      if (name == null ||
          code == null ||
          !RegExp(r'^[A-Z]{2}$').hasMatch(code)) {
        continue;
      }
      try {
        return CitySelection(
          cityName: name,
          countryName: (place.country?.trim().isNotEmpty ?? false)
              ? place.country!
              : code,
          countryCode: code,
          latitude: latitude,
          longitude: longitude,
        );
      } on FormatException {
        continue;
      }
    }
    return null;
  }
}
