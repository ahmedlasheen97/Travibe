import 'buddies_filters.dart';
import 'buddies_home_response.dart';

class BuddiesPage {
  BuddiesPage._({
    required this.items,
    required this.links,
    required this.currentPage,
    required this.lastPage,
    required this.perPage,
    required this.total,
    this.hasCurrentCity,
    this.city,
    this.countryCode,
    this.searchPage = false,
  });
  final List<BuddyResource> items;
  final Map<String, String?> links;
  final int currentPage, lastPage, perPage, total;
  final bool? hasCurrentCity;
  final String? city, countryCode;
  final bool searchPage;
  String? get next =>
      searchPage && currentPage >= lastPage ? null : links['next'];

  factory BuddiesPage.fromJson(dynamic json, BuddiesListing listing) =>
      BuddiesPage._parse(json, cityMetadata: listing == BuddiesListing.city);

  factory BuddiesPage.search(dynamic json) =>
      BuddiesPage._parse(json, cityMetadata: false, searchPage: true);

  static BuddiesPage _parse(
    dynamic json, {
    required bool cityMetadata,
    bool searchPage = false,
  }) {
    if (json is! Map<String, dynamic> ||
        json['data'] is! List ||
        json['links'] is! Map ||
        json['meta'] is! Map) {
      throw const FormatException('Invalid discovery page');
    }
    final meta = json['meta'] as Map;
    int number(String key, int minimum) {
      final value = meta[key];
      if (value is! int || value < minimum) {
        throw FormatException('Invalid $key');
      }
      return value;
    }

    final links = <String, String?>{};
    for (final key in ['first', 'last', 'prev', 'next']) {
      final value = json['links'][key];
      if (!json['links'].containsKey(key) ||
          (value != null && value is! String)) {
        throw FormatException('Invalid link $key');
      }
      links[key] = value as String?;
    }
    String? city, country;
    bool? hasCity;
    if (cityMetadata) {
      if (meta['has_current_city'] is! bool ||
          !meta.containsKey('current_city')) {
        throw const FormatException('Invalid city metadata');
      }
      hasCity = meta['has_current_city'] as bool;
      final current = meta['current_city'];
      if (current != null) {
        if (current is! Map ||
            (current['city'] != null && current['city'] is! String) ||
            (current['country_code'] != null &&
                current['country_code'] is! String)) {
          throw const FormatException('Invalid city');
        }
        city = current['city'] as String?;
        country = current['country_code'] as String?;
      }
    }
    final perPage = number('per_page', 1);
    if (perPage > 100) throw const FormatException('Invalid per_page');
    return BuddiesPage._(
      items: List.unmodifiable(
        (json['data'] as List).map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('Invalid buddy');
          }
          return BuddyResource.fromJson(item);
        }),
      ),
      links: Map.unmodifiable(links),
      currentPage: number('current_page', 1),
      lastPage: number('last_page', 1),
      perPage: perPage,
      searchPage: searchPage,
      total: number('total', 0),
      hasCurrentCity: hasCity,
      city: city,
      countryCode: country,
    );
  }
}
