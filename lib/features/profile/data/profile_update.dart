import 'package:travibe/core/places/city_places_provider.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/profile/data/profile_model.dart';

/// Presence is significant: absent keys preserve values; null clears them.
class ProfileUpdate {
  ProfileUpdate(Map<String, dynamic> changes)
    : _changes = Map.unmodifiable(
        changes.map(
          (key, value) =>
              MapEntry(key, value is List ? List.unmodifiable(value) : value),
        ),
      ) {
    final errors = validate(_changes);
    if (errors.isNotEmpty) {
      throw ApiError(message: errors.values.first.first, fieldErrors: errors);
    }
  }
  final Map<String, dynamic> _changes;
  bool get isEmpty => _changes.isEmpty;
  Map<String, dynamic> toJson() => Map.of(_changes);

  static Map<String, List<String>> validate(Map<String, dynamic> values) {
    final errors = <String, List<String>>{};
    void invalid(String field, String message) => errors[field] = [message];
    for (final entry in values.entries) {
      final key = entry.key;
      final value = entry.value;
      switch (key) {
        case 'full_name':
          if (value is! String ||
              value.trim().isEmpty ||
              value.runes.length > 255) {
            invalid(key, 'Enter a full name of 1–255 characters.');
          }
        case 'username':
          if (value != null &&
              (value is! String ||
                  !RegExp(r'^[a-zA-Z0-9_.]{3,30}$').hasMatch(value))) {
            invalid(key, 'Use 3–30 letters, numbers, underscores or periods.');
          }
        case 'bio':
          if (value != null && (value is! String || value.runes.length > 180)) {
            invalid(key, 'Bio must be at most 180 characters.');
          }
        case 'country_code':
        case 'nationality_code':
          if (value != null &&
              (value is! String ||
                  !RegExp(r'^[A-Z]{2}$').hasMatch(value) ||
                  ['AC', 'XK'].contains(value) ||
                  Country.tryParse(value)?.countryCode != value)) {
            invalid(key, 'Select a valid two-letter country code.');
          }
        case 'gender':
          if (value != null && !['male', 'female', 'other'].contains(value)) {
            invalid(key, 'Select male, female or other.');
          }
        case 'avatar_media_id':
          if (value != null && (value is! int || value < 1)) {
            invalid(key, 'Invalid avatar media ID.');
          }
        case 'languages_spoken':
        case 'interests':
        case 'travel_styles':
          final max = key == 'languages_spoken'
              ? 4
              : key == 'interests'
              ? 6
              : 3;
          if (value != null &&
              (value is! List ||
                  value.isEmpty ||
                  value.length > max ||
                  value.any((e) => e is! String || e.trim().isEmpty) ||
                  value.toSet().length != value.length)) {
            invalid(
              key,
              'Select 1–$max distinct options, or explicitly clear the selection.',
            );
          }
        default:
          invalid(key, 'Unsupported profile field.');
      }
    }
    return errors;
  }
}

class ProfileDraft {
  ProfileDraft(ProfileModel profile)
    : profileId = profile.id,
      _savedLocation = profile.currentLocation,
      _location = profile.currentLocation,
      _original = {
        'full_name': profile.name,
        'username': profile.username,
        'bio': profile.bio,
        'country_code': profile.countryCode,
        'nationality_code': profile.nationalityCode,
        'gender': profile.gender,
        'languages_spoken': profile.languageSelections
            .map((e) => e.slug)
            .toList(),
        'interests': profile.interestSelections.map((e) => e.slug).toList(),
        'travel_styles': profile.travelStyleSelections
            .map((e) => e.slug)
            .toList(),
      };
  final String profileId;
  final Map<String, dynamic> _original;
  final Map<String, dynamic> _changes = {};
  Map<String, dynamic> get changes => Map.unmodifiable(_changes);
  String? _savedLocation, _location;
  CitySelection? _city;
  String? get currentLocation => _location;
  CitySelection? get selectedCity => _city;
  bool get hasLocationChange => !_sameLocation(_savedLocation, _location);
  bool get isDirty => _changes.isNotEmpty || hasLocationChange;
  static bool _sameLocation(String? a, String? b) =>
      (a?.trim().toLowerCase() ?? '') == (b?.trim().toLowerCase() ?? '');

  void selectCity(CitySelection? city) {
    _city = city;
    _location = city == null ? null : '${city.cityName}, ${city.countryCode}';
  }

  void markLocationSaved({
    required String? submitted,
    required String? canonical,
  }) {
    final unchanged = _sameLocation(_location, submitted);
    _savedLocation = canonical;
    if (unchanged) _location = canonical;
  }

  bool get clearsRequired => [
    'username',
    'languages_spoken',
    'interests',
    'travel_styles',
  ].any((key) => _changes.containsKey(key) && _changes[key] == null);

  void set(String key, dynamic value) {
    if (value is List) value = List.unmodifiable(value);
    final old = _original[key];
    final equal = old is List && value is List
        ? setEquals(old.toSet(), value.toSet())
        : old == value ||
              ((old == null || old is List && old.isEmpty) && value == null);
    if (equal) {
      _changes.remove(key);
    } else {
      _changes[key] = value;
    }
  }

  /// Acknowledge only the fields included in a successful PATCH. Later edits
  /// remain dirty, including an edit that reverted while the request was pending.
  void markSaved(ProfileUpdate update) {
    for (final entry in update.toJson().entries) {
      final current = _changes.containsKey(entry.key)
          ? _changes[entry.key]
          : _original[entry.key];
      _original[entry.key] = entry.value;
      set(entry.key, current);
    }
  }

  ProfileUpdate toUpdate() => ProfileUpdate(_changes);
}
