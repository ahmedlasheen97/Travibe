import 'package:flutter/foundation.dart';
import 'buddies_filters.dart';

@immutable
class BuddiesSearchQuery {
  BuddiesSearchQuery({
    required String city,
    this.countryCode,
    BuddiesFilters? filters,
    this.perPage = 15,
  }) : city = city.trim(),
       filters = filters ?? BuddiesFilters() {
    if (this.city.isEmpty || this.city.runes.length > 120) {
      throw ArgumentError.value(city, 'city', 'Use 1–120 characters.');
    }
    if (countryCode != null && !RegExp(r'^[A-Z]{2}$').hasMatch(countryCode!)) {
      throw ArgumentError.value(countryCode, 'countryCode');
    }
    if (perPage < 1 || perPage > 100) {
      throw ArgumentError.value(perPage, 'perPage');
    }
  }
  final String city;
  final String? countryCode;
  final BuddiesFilters filters;
  final int perPage;

  Map<String, dynamic> toQuery() => {
    'city': city,
    if (countryCode != null) 'country_code': countryCode,
    'page': 1,
    'per_page': perPage,
    ...filters.toQuery(),
  };

  @override
  bool operator ==(Object other) =>
      other is BuddiesSearchQuery &&
      city == other.city &&
      countryCode == other.countryCode &&
      filters == other.filters &&
      perPage == other.perPage;
  @override
  int get hashCode => Object.hash(city, countryCode, filters, perPage);
}
