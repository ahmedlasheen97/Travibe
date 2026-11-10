import 'buddies_filters.dart';
import 'buddies_page.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'buddies_home_response.dart';
import 'buddies_search_query.dart';

class BuddiesRepo {
  BuddiesRepo({ApiService? apiService}) : _api = apiService ?? ApiService();
  final ApiService _api;
  Future<void> saveRecentDestination(String destination) async {
    await _api.post('buddies/search/recent', {'destination': destination});
  }

  Future<BuddiesHomeResponse> getHome() async {
    final response = await _api.get('buddies');
    try {
      if (response is! Map<String, dynamic>) throw const FormatException();
      return BuddiesHomeResponse.fromJson(response);
    } on FormatException {
      throw ApiError(
        message: 'Unable to read traveler discovery. Please try again.',
      );
    }
  }

  Future<BuddiesPage> getInYourCity({
    BuddiesFilters? filters,
    int perPage = 15,
    String? next,
  }) => getListing(
    BuddiesListing.city,
    filters: filters,
    perPage: perPage,
    next: next,
  );

  Future<BuddiesPage> getWithSameInterests({
    BuddiesFilters? filters,
    int perPage = 15,
    String? next,
  }) => getListing(
    BuddiesListing.interests,
    filters: filters,
    perPage: perPage,
    next: next,
  );

  /// Never forward authentication to a foreign host or another API route.
  static String safeNext(BuddiesListing listing, String value) =>
      _safeNext(listing.endpoint, value);
  static String safeSearchNext(String value) {
    final next = _safeNext('buddies/search', value);
    final page = int.tryParse(Uri.parse(next).queryParameters['page'] ?? '');
    if (page == null || page < 1) {
      throw ApiError(
        message: 'The server returned an invalid search page link.',
      );
    }
    return next;
  }

  static String _safeNext(String endpoint, String value) {
    final base = Uri.parse('https://travibeapp.com/api/v1/$endpoint');
    final Uri uri;
    try {
      uri = base.resolve(value);
    } on FormatException {
      throw ApiError(
        message: 'The server returned an invalid pagination link.',
      );
    }
    if (uri.scheme != 'https' ||
        uri.host != base.host ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.path != base.path ||
        value.contains('\\')) {
      throw ApiError(message: 'The server returned an unsafe pagination link.');
    }
    return uri.toString();
  }

  /// Compare equivalent relative/absolute links and query ordering without
  /// interpreting or constructing the server's pagination parameters.
  static String paginationKey(BuddiesListing listing, String value) {
    return _paginationKey(safeNext(listing, value));
  }

  static String searchPaginationKey(String value) =>
      _paginationKey(safeSearchNext(value));

  static String _paginationKey(String value) {
    final uri = Uri.parse(value);
    final query = uri.queryParametersAll;
    final keys = query.keys.toList()..sort();
    return uri
        .replace(queryParameters: {for (final key in keys) key: query[key]!})
        .toString();
  }

  Future<BuddiesPage> search({
    required BuddiesSearchQuery query,
    String? next,
  }) async {
    final target = next == null
        ? null
        : _continuation(
            safeSearchNext(next),
            query.filters,
            parameters: Map.of(query.toQuery())..remove('page'),
          );
    final response = await _api.get(
      target ?? 'buddies/search',
      queryParameters: next == null ? query.toQuery() : null,
    );
    try {
      return BuddiesPage.search(response);
    } on FormatException {
      throw ApiError(
        message: 'Unable to read the traveler search. Please try again.',
      );
    }
  }

  static String _continuation(
    String next,
    BuddiesFilters? filters, {
    Map<String, dynamic> parameters = const {},
  }) {
    final uri = Uri.parse(next);
    final query = <String, dynamic>{...uri.queryParametersAll};
    if (parameters.containsKey('city')) {
      query.removeWhere((key, _) => key != 'page');
    }
    for (final name in [
      'gender',
      'nationality',
      'languages',
      'interests',
      'travel_styles',
      ...parameters.keys,
      if (parameters.containsKey('city')) ...[
        'country_code',
        'cursor',
        // Discard obsolete trip-search parameters even in cached server links.
        'destination',
        'destination_city',
        'destination_country_code',
        'sort',
        'trip',
        'starts_on',
        'ends_on',
      ],
    ]) {
      query.removeWhere((key, _) => key == name || key.startsWith('$name['));
    }
    // Keep the server's opaque continuation, but never let it change the query.
    query.addAll(filters?.toQuery() ?? {});
    query.addAll(parameters);
    return uri
        .replace(
          queryParameters: {
            for (final entry in query.entries)
              entry.key: entry.value is Iterable
                  ? (entry.value as Iterable).map((value) => value.toString())
                  : entry.value.toString(),
          },
        )
        .toString();
  }

  Future<BuddiesPage> getListing(
    BuddiesListing listing, {
    BuddiesFilters? filters,
    int perPage = 15,
    String? next,
  }) async {
    if (perPage < 1 || perPage > 100) {
      throw ArgumentError.value(perPage, 'perPage');
    }
    String? target;
    if (next != null) {
      target = _continuation(safeNext(listing, next), filters);
    }
    final response = await _api.get(
      target ?? listing.endpoint,
      queryParameters: next == null
          ? {'per_page': perPage, ...?filters?.toQuery()}
          : null,
    );
    try {
      return BuddiesPage.fromJson(response, listing);
    } on FormatException {
      throw ApiError(
        message: 'Unable to read the traveler list. Please try again.',
      );
    }
  }
}
