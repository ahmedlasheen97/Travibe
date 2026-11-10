import 'package:travibe/core/datasource/remotedata/api_error.dart';

// Display labels from the original Figma UI. These are not API values.
const profileLanguageOptions = [
  'English',
  'Arabic',
  'French',
  'German',
  'Portuguese',
  'Korean',
];

const profileInterestOptions = [
  'Hiking',
  'Photography',
  'Beach',
  'Culture',
  'Adventure',
  'Nightlife',
  'Food',
  'Nature',
  'Camping',
  'History',
  'Road Trips',
  'Luxury',
];

// Canonical slugs verified against live API responses by the backend team.
// Keep these explicit: display labels must never be converted heuristically.
const profileLanguageSlugs = {
  'English': 'english',
  'Arabic': 'arabic',
  'French': 'french',
  'German': 'german',
  'Portuguese': 'portuguese',
  'Korean': 'korean',
};

const profileInterestSlugs = {
  'Hiking': 'hiking',
  'Photography': 'photography',
  'Beach': 'beach',
  'Culture': 'culture',
  'Adventure': 'adventure',
  'Nightlife': 'nightlife',
  'Food': 'food',
  'Nature': 'nature',
  'Camping': 'camping',
  'History': 'history',
  'Road Trips': 'road_trips',
  'Luxury': 'luxury',
};

List<String>? serializeProfileSelections(
  List<String>? selected, {
  required Map<String, String> mapping,
  required int limit,
  required String field,
  Iterable<String> verifiedSlugs = const [],
}) {
  if (selected == null) return null;
  if (selected.length > limit) {
    throw ApiError(message: 'Select up to $limit distinct $field.');
  }
  final slugs = selected.map((value) {
    // Also accept canonical values from existing repository callers.
    final slug =
        mapping[value] ??
        (mapping.containsValue(value) || verifiedSlugs.contains(value)
            ? value
            : null);
    if (slug == null) {
      throw ApiError(message: 'Unsupported $field option: "$value".');
    }
    return slug;
  }).toList();
  if (slugs.toSet().length != slugs.length) {
    throw ApiError(message: 'Select distinct $field.');
  }
  return List.unmodifiable(slugs);
}
