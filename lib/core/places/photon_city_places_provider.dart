import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'city_places_provider.dart';

/// Public geocoding uses a separate Dio: never forward Travibe's Bearer token.
class PhotonCityPlacesProvider
    implements CityPlacesProvider, CityReverseGeocoder {
  PhotonCityPlacesProvider({
    Dio? transport,
    DateTime Function()? now,
    this.debugLogging = const bool.fromEnvironment('PHOTON_DEBUG'),
  }) : _now = now ?? DateTime.now,
       _http =
           transport ??
           Dio(
             BaseOptions(
               connectTimeout: requestTimeout,
               sendTimeout: requestTimeout,
               receiveTimeout: requestTimeout,
               headers: {'Accept': 'application/json'},
             ),
           );
  static const endpoint = 'https://photon.komoot.io/api/';
  // Identify this app honestly. The public service rejects Dart's generic UA.
  static const userAgent = 'Travibe/1.0 (https://travibeapp.com)';
  static const requestTimeout = Duration(seconds: 8);
  final Dio _http;
  final DateTime Function() _now;
  final bool debugLogging;
  DateTime? _retryAt;
  final Map<String, Future<List<CitySuggestion>>> _pending = {};

  @override
  Future<List<CitySuggestion>> autocomplete(String input) {
    final query = input.trim();
    if (query.runes.length < 2 || query.runes.length > 120) {
      return Future.value([]);
    }
    if (_retryAt != null && _now().isBefore(_retryAt!)) {
      return Future.error(CityPlacesException(_busyMessage()));
    }
    final pending = _pending[query];
    if (pending != null) return pending;
    final request = _search(query);
    _pending[query] = request;
    return request.whenComplete(() => _pending.remove(query));
  }

  Future<List<CitySuggestion>> _search(String query) =>
      _request({'q': query, 'limit': 6, 'lang': 'en', 'osm_tag': 'place:city'});

  @override
  Future<CitySelection> reverse(double latitude, double longitude) async {
    if (!latitude.isFinite ||
        latitude.abs() > 90 ||
        !longitude.isFinite ||
        longitude.abs() > 180) {
      throw const CityPlacesException(
        'Invalid device coordinates. Choose a city manually.',
      );
    }
    if (_retryAt != null && _now().isBefore(_retryAt!)) {
      throw CityPlacesException(_busyMessage());
    }
    final cities = await _request({
      'lat': latitude,
      'lon': longitude,
      'limit': 6,
      'lang': 'en',
      'layer': 'city',
    }, reverse: true);
    if (cities.isEmpty) {
      throw const CityPlacesException(
        'No usable city was found at your location. Choose a city manually.',
      );
    }
    return cities.first.selection!;
  }

  Future<List<CitySuggestion>> _request(
    Map<String, dynamic> parameters, {
    bool reverse = false,
  }) async {
    final cancel = CancelToken();
    final elapsed = Stopwatch()..start();
    final target = reverse ? 'https://photon.komoot.io/reverse' : endpoint;
    _log('GET $target parameters=<redacted>');
    try {
      final response = await _http
          .get<dynamic>(
            target,
            queryParameters: parameters,
            cancelToken: cancel,
            options: Options(
              headers: {'User-Agent': userAgent},
              followRedirects: false,
              sendTimeout: requestTimeout,
              receiveTimeout: requestTimeout,
            ),
          )
          .timeout(
            requestTimeout,
            onTimeout: () {
              cancel.cancel('City request timed out.');
              throw TimeoutException('City request timed out.');
            },
          );
      _log('status=${response.statusCode} body=${_bodyShape(response.data)}');
      if (response.statusCode != 200) _rejectHttp(response);
      final cities = parse(response.data, allowTowns: reverse);
      _log('parsedCities=${cities.length}');
      return cities;
    } on TimeoutException {
      _log('exception=TimeoutException');
      throw const CityPlacesException(
        'City search timed out. Please try again.',
      );
    } on DioException catch (error) {
      _log(
        'exception=${error.type.name} cause=${error.error.runtimeType} '
        'status=${error.response?.statusCode} '
        'body=${_bodyShape(error.response?.data)}',
      );
      if (error.response != null && error.response!.statusCode != 200) {
        _rejectHttp(error.response!);
      }
      if ([
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ].contains(error.type)) {
        throw const CityPlacesException(
          'City search timed out. Please try again.',
        );
      }
      if (error.error is FormatException) {
        throw const CityPlacesException(
          'Unable to read city suggestions. Try again.',
        );
      }
      // Dio may wrap interceptor/transformer bugs. Keep them observable.
      if (error.error is Error) {
        Error.throwWithStackTrace(error.error!, error.stackTrace);
      }
      if (error.type == DioExceptionType.badCertificate) {
        throw const CityPlacesException(
          'Unable to securely connect to city search. Please try again.',
        );
      }
      throw const CityPlacesException(
        'Unable to connect to city search. Check your connection and try again.',
      );
    } on FormatException {
      _log('exception=FormatException');
      throw const CityPlacesException(
        'Unable to read city suggestions. Try again.',
      );
    } finally {
      _log('completed elapsedMs=${elapsed.elapsedMilliseconds}');
    }
  }

  Never _rejectHttp(Response<dynamic> response) {
    final status = response.statusCode;
    if (status == 429) {
      final seconds = int.tryParse(response.headers.value('retry-after') ?? '');
      // Unknown/missing Retry-After gets a conservative cooldown; no auto retry.
      final delay = seconds != null && seconds >= 0 && seconds <= 86400
          ? seconds
          : 30;
      _retryAt = _now().add(Duration(seconds: delay));
      throw CityPlacesException(_busyMessage());
    }
    if (status == 401 || status == 403) {
      throw CityPlacesException(
        'City suggestions service denied access ($status). Please try again later.',
      );
    }
    if (status != null && status >= 500) {
      throw CityPlacesException(
        'City search service is temporarily unavailable ($status). Please try again.',
      );
    }
    throw CityPlacesException(
      'City search request failed (HTTP $status). Please try again.',
    );
  }

  String _busyMessage() {
    final seconds = ((_retryAt!.difference(_now()).inMilliseconds) / 1000)
        .ceil();
    return seconds > 0
        ? 'City search is busy. Try again in $seconds seconds.'
        : 'City search is busy. Please try again shortly.';
  }

  String _bodyShape(dynamic body) {
    if (body is Map &&
        body['type'] == 'FeatureCollection' &&
        body['features'] is List) {
      return 'FeatureCollection(features=${(body['features'] as List).length})';
    }
    return body is String
        ? 'text(length=${body.length})'
        : '${body.runtimeType}';
  }

  void _log(String message) {
    if (kDebugMode && debugLogging) debugPrint('[Photon] $message');
  }

  /// Invalid individual features are skipped; a malformed collection is an error.
  static List<CitySuggestion> parse(dynamic body, {bool allowTowns = false}) {
    if (body is! Map ||
        body['type'] != 'FeatureCollection' ||
        body['features'] is! List) {
      throw const FormatException('Invalid city collection');
    }
    final cities = <String, CitySuggestion>{};
    for (final feature in body['features'] as List) {
      if (feature is! Map || feature['type'] != 'Feature') continue;
      final properties = feature['properties'];
      final geometry = feature['geometry'];
      if (properties is! Map ||
          geometry is! Map ||
          geometry['type'] != 'Point') {
        continue;
      }
      // A server filter is necessary, but validate any explicit classification
      // too so unexpected streets, buildings or towns cannot enter city results.
      if ((properties['osm_key'] != null && properties['osm_key'] != 'place') ||
          (properties['osm_value'] != null &&
              properties['osm_value'] != 'city' &&
              !(allowTowns && properties['osm_value'] == 'town')) ||
          (properties['type'] != null &&
              properties['type'] != 'city' &&
              !(allowTowns && properties['type'] == 'town'))) {
        continue;
      }
      final coordinates = geometry['coordinates'];
      if (coordinates is! List ||
          coordinates.length != 2 ||
          coordinates[0] is! num ||
          coordinates[1] is! num ||
          properties['name'] is! String ||
          properties['country'] is! String ||
          properties['countrycode'] is! String) {
        continue;
      }
      final osmType = properties['osm_type'];
      final osmId = properties['osm_id'];
      final externalId =
          osmType is String &&
              {'N', 'W', 'R'}.contains(osmType) &&
              osmId is int &&
              osmId > 0
          ? '$osmType:$osmId'
          : null;
      try {
        final city = CitySelection(
          cityName: properties['name'],
          countryName: properties['country'],
          countryCode: properties['countrycode'],
          longitude: (coordinates[0] as num).toDouble(),
          latitude: (coordinates[1] as num).toDouble(),
          externalId: externalId,
        );
        // Missing OSM IDs don't prevent selection; the fallback is only an internal
        // UI key and is never represented as an external OSM identifier.
        final identity =
            externalId ??
            jsonEncode([
              city.cityName,
              city.countryCode,
              city.longitude,
              city.latitude,
            ]);
        final state = properties['state'];
        final label = [
          city.cityName,
          if (state is String &&
              state.trim().isNotEmpty &&
              state.trim() != city.cityName &&
              state.trim() != city.countryName)
            state.trim(),
          city.countryName,
        ].join(', ');
        cities.putIfAbsent(
          identity,
          () => CitySuggestion(id: identity, label: label, selection: city),
        );
      } on FormatException {
        continue;
      }
      if (cities.length == 6) break;
    }
    return List.unmodifiable(cities.values);
  }

  @override
  Future<CitySelection> resolve(CitySuggestion suggestion) async {
    final city = suggestion.selection;
    if (city == null) {
      throw const CityPlacesException(
        'Unable to confirm this city. Choose a city again.',
      );
    }
    return city; // Photon already returned all validated fields; no details call.
  }
}
