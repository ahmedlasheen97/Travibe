import 'package:flutter/foundation.dart';

@immutable
class BuddiesFilters {
  BuddiesFilters({
    Iterable<String> gender = const [],
    Iterable<String> nationality = const [],
    Iterable<String> languages = const [],
    Iterable<String> interests = const [],
    Iterable<String> travelStyles = const [],
  }) : gender = Set.unmodifiable(gender),
       nationality = Set.unmodifiable(nationality),
       languages = Set.unmodifiable(languages),
       interests = Set.unmodifiable(interests),
       travelStyles = Set.unmodifiable(travelStyles) {
    if (this.gender.any((value) => !{'male', 'female'}.contains(value)) ||
        this.nationality.any(
          (value) => !RegExp(r'^[A-Z]{2}$').hasMatch(value),
        ) ||
        [
          ...this.languages,
          ...this.interests,
          ...this.travelStyles,
        ].any((value) => value.trim().isEmpty)) {
      throw ArgumentError('Invalid discovery filters');
    }
  }
  final Set<String> gender, nationality, languages, interests, travelStyles;
  Map<String, dynamic> toQuery() => {
    if (gender.isNotEmpty) 'gender[]': gender.toList(),
    if (nationality.isNotEmpty) 'nationality[]': nationality.toList(),
    if (languages.isNotEmpty) 'languages[]': languages.toList(),
    if (interests.isNotEmpty) 'interests[]': interests.toList(),
    if (travelStyles.isNotEmpty) 'travel_styles[]': travelStyles.toList(),
  };
  @override
  bool operator ==(Object other) =>
      other is BuddiesFilters &&
      setEquals(gender, other.gender) &&
      setEquals(nationality, other.nationality) &&
      setEquals(languages, other.languages) &&
      setEquals(interests, other.interests) &&
      setEquals(travelStyles, other.travelStyles);
  @override
  int get hashCode => Object.hashAll([
    Object.hashAllUnordered(gender),
    Object.hashAllUnordered(nationality),
    Object.hashAllUnordered(languages),
    Object.hashAllUnordered(interests),
    Object.hashAllUnordered(travelStyles),
  ]);
}

enum BuddiesListing {
  city('in-your-city', 'In Your City'),
  interests('with-same-interests', 'With Same Interests');

  const BuddiesListing(this.path, this.title);
  final String path, title;
  String get endpoint => 'buddies/$path';
}
