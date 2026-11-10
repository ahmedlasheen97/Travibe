import 'package:flutter/foundation.dart';

@immutable
class CitySuggestion {
  const CitySuggestion({required this.id, required this.label, this.selection});

  /// Internal UI identity, independent of whether an OSM identifier is available.
  final String id;
  final String label;
  final CitySelection? selection;
}

@immutable
class CitySelection {
  CitySelection({
    required String cityName,
    required String countryName,
    required String countryCode,
    required this.latitude,
    required this.longitude,
    this.externalId,
  }) : cityName = cityName.trim(),
       countryName = countryName.trim(),
       countryCode = countryCode.trim().toUpperCase() {
    if (this.cityName.isEmpty ||
        this.cityName.runes.length > 120 ||
        this.countryName.isEmpty ||
        !RegExp(r'^[A-Z]{2}$').hasMatch(this.countryCode) ||
        !latitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        !longitude.isFinite ||
        longitude < -180 ||
        longitude > 180 ||
        externalId != null &&
            !RegExp(r'^[NWR]:[1-9][0-9]*$').hasMatch(externalId!)) {
      throw const FormatException('Invalid resolved city');
    }
  }
  final String cityName, countryName, countryCode;
  final double latitude, longitude;
  final String? externalId;
  String get label => '$cityName, $countryName';
}

class CityPlacesException implements Exception {
  const CityPlacesException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class CityPlacesProvider {
  Future<List<CitySuggestion>> autocomplete(String input);
  Future<CitySelection> resolve(CitySuggestion suggestion);
}

abstract interface class CityReverseGeocoder {
  Future<CitySelection> reverse(double latitude, double longitude);
}
