import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/places/city_places_provider.dart';
import 'package:travibe/core/places/photon_city_places_provider.dart';

Map<String, dynamic> photonFeature({
  String name = 'Dubai',
  String country = 'United Arab Emirates',
  String code = 'AE',
  int id = 1234,
  double lon = 55.2708,
  double lat = 25.2048,
}) => {
  'type': 'Feature',
  'properties': <String, dynamic>{
    'name': name,
    'country': country,
    'countrycode': code,
    'osm_type': 'N',
    'osm_id': id,
    'osm_key': 'place',
    'osm_value': 'city',
    'type': 'city',
  },
  'geometry': <String, dynamic>{
    'type': 'Point',
    'coordinates': [lon, lat],
  },
};
Map<String, dynamic> photonCollection(List<dynamic> features) => {
  'type': 'FeatureCollection',
  'features': features,
};

class PhotonAdapter implements HttpClientAdapter {
  dynamic data = photonCollection([photonFeature()]);
  int status = 200;
  DioExceptionType? failure;
  Completer<ResponseBody>? pending;
  final requests = <RequestOptions>[];
  final headers = <String, List<String>>{
    Headers.contentTypeHeader: [Headers.jsonContentType],
  };
  Object? cause;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (failure != null) {
      throw DioException(requestOptions: options, type: failure!, error: cause);
    }
    if (pending != null) return pending!.future;
    return ResponseBody.fromString(jsonEncode(data), status, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late PhotonAdapter adapter;
  late PhotonCityPlacesProvider provider;
  setUp(() {
    adapter = PhotonAdapter();
    provider = PhotonCityPlacesProvider(
      transport: Dio()..httpClientAdapter = adapter,
    );
  });

  test(
    'GET worldwide city query has exact parameters, no Bearer and eight-second timeout',
    () async {
      await provider.autocomplete(' Dub ');
      final request = adapter.requests.single;
      expect(
        request.uri.origin + request.uri.path,
        'https://photon.komoot.io/api/',
      );
      expect(request.method, 'GET');
      expect(request.queryParameters, {
        'q': 'Dub',
        'limit': 6,
        'lang': 'en',
        'osm_tag': 'place:city',
      });
      expect(request.receiveTimeout, const Duration(seconds: 8));
      expect(request.sendTimeout, const Duration(seconds: 8));
      expect(request.headers.containsKey('Authorization'), false);
      // Verified on iOS: the generic Dart UA receives nginx 403; this app UA 200.
      expect(
        request.headers['User-Agent'],
        'Travibe/1.0 (https://travibeapp.com)',
      );
      expect(request.followRedirects, false);
      expect(request.data, isNull);
    },
  );
  test(
    'GeoJSON longitude/latitude order, country normalization and local resolution',
    () async {
      adapter.data = photonCollection([photonFeature(code: ' ae ')]);
      final suggestion = (await provider.autocomplete('Dub')).single;
      final city = await provider.resolve(suggestion);
      expect(city.cityName, 'Dubai');
      expect(city.countryName, 'United Arab Emirates');
      expect(city.countryCode, 'AE');
      expect(city.longitude, 55.2708);
      expect(city.latitude, 25.2048);
      expect(city.externalId, 'N:1234');
      expect(suggestion.label, 'Dubai, United Arab Emirates');
      expect(adapter.requests.length, 1);
    },
  );
  test(
    'same-name cities in different countries and states remain distinct',
    () async {
      final canada = photonFeature(
        name: 'London',
        country: 'Canada',
        code: 'ca',
        id: 2,
      );
      (canada['properties'] as Map)['state'] = 'Ontario';
      adapter.data = photonCollection([
        photonFeature(name: 'London', country: 'United Kingdom', code: 'GB'),
        canada,
      ]);
      final results = await provider.autocomplete('Lon');
      expect(results.map((s) => s.label), [
        'London, United Kingdom',
        'London, Ontario, Canada',
      ]);
      expect(results.map((s) => s.selection!.countryCode), ['GB', 'CA']);
    },
  );
  test(
    'duplicate OSM IDs deduplicate, but node and relation IDs remain distinct',
    () async {
      final relation = photonFeature();
      (relation['properties'] as Map)['osm_type'] = 'R';
      adapter.data = photonCollection([
        photonFeature(),
        photonFeature(),
        relation,
      ]);
      expect((await provider.autocomplete('Dub')).map((s) => s.id), [
        'N:1234',
        'R:1234',
      ]);
    },
  );
  test(
    'missing and invalid external identifiers stay null without dropping valid cities',
    () async {
      for (final values in [
        <String, dynamic>{},
        {'osm_type': 'N'},
        {'osm_id': 1234},
        {'osm_type': 'X', 'osm_id': 1234},
        {'osm_type': 'N', 'osm_id': 0},
        {'osm_type': 'W', 'osm_id': '1234'},
      ]) {
        final feature = photonFeature();
        final props = feature['properties'] as Map;
        props.remove('osm_type');
        props.remove('osm_id');
        props.addAll(values);
        final city = PhotonCityPlacesProvider.parse(
          photonCollection([feature]),
        ).single.selection!;
        expect(city.externalId, isNull);
      }
    },
  );
  for (final field in ['name', 'country', 'countrycode']) {
    test('incomplete $field is skipped while valid features survive', () {
      final bad = photonFeature();
      (bad['properties'] as Map).remove(field);
      expect(
        PhotonCityPlacesProvider.parse(
          photonCollection([bad, photonFeature(id: 2)]),
        ).single.id,
        'N:2',
      );
    });
  }
  for (final code in ['', 'A', 'United Arab Emirates', 'A1', 'AAA']) {
    test('invalid country code $code is never guessed', () {
      expect(
        PhotonCityPlacesProvider.parse(
          photonCollection([photonFeature(code: code)]),
        ),
        isEmpty,
      );
    });
  }
  for (final coords in [
    <dynamic>[181, 0],
    [-181, 0],
    [0, 91],
    [0, -91],
    [double.nan, 0],
    [0, double.infinity],
    ['55', 25],
    [55],
    [55, 25, 5],
    null,
  ]) {
    test('invalid coordinates $coords are skipped', () {
      final bad = photonFeature();
      (bad['geometry'] as Map)['coordinates'] = coords;
      expect(PhotonCityPlacesProvider.parse(photonCollection([bad])), isEmpty);
    });
  }
  test(
    'Point geometry and nonempty names are required; missing properties are safe',
    () {
      final polygon = photonFeature();
      (polygon['geometry'] as Map)['type'] = 'Polygon';
      final missing = photonFeature()..remove('properties');
      final blank = photonFeature(name: '   ');
      expect(
        PhotonCityPlacesProvider.parse(
          photonCollection([null, polygon, missing, blank, {}]),
        ),
        isEmpty,
      );
    },
  );
  test(
    'boundary coordinates and missing optional classification tags are accepted',
    () {
      final feature = photonFeature(lon: 180, lat: -90);
      final props = feature['properties'] as Map;
      props.remove('osm_key');
      props.remove('osm_value');
      props.remove('type');
      expect(
        PhotonCityPlacesProvider.parse(
          photonCollection([feature]),
        ).single.selection!.latitude,
        -90,
      );
    },
  );
  for (final classification in [
    {'osm_key': 'highway'},
    {'osm_value': 'town'},
    {'type': 'street'},
    {'osm_value': 'building'},
  ]) {
    test('explicit unrelated classification $classification is excluded', () {
      final feature = photonFeature();
      (feature['properties'] as Map).addAll(classification);
      expect(
        PhotonCityPlacesProvider.parse(photonCollection([feature])),
        isEmpty,
      );
    });
  }
  test(
    'empty collections are valid, malformed collection shapes fail visibly',
    () async {
      adapter.data = photonCollection([]);
      expect(await provider.autocomplete('zz'), isEmpty);
      for (final data in [
        null,
        [],
        {},
        {'type': 'FeatureCollection', 'features': 'bad'},
      ]) {
        adapter.data = data;
        await expectLater(
          provider.autocomplete('zz'),
          throwsA(isA<CityPlacesException>()),
        );
      }
    },
  );
  for (final status in [400, 401, 403, 429, 500, 503]) {
    test('HTTP $status is a safe retryable failure', () async {
      adapter.status = status;
      await expectLater(
        provider.autocomplete('Dub'),
        throwsA(isA<CityPlacesException>()),
      );
    });
  }
  test(
    '429 respects numeric Retry-After across queries, with manual retry only',
    () async {
      var now = DateTime.utc(2026, 10, 28);
      provider = PhotonCityPlacesProvider(
        transport: Dio()..httpClientAdapter = adapter,
        now: () => now,
      );
      adapter.status = 429;
      adapter.headers['retry-after'] = ['12'];
      await expectLater(
        provider.autocomplete('cai'),
        throwsA(
          isA<CityPlacesException>().having(
            (e) => e.message,
            'message',
            contains('12 seconds'),
          ),
        ),
      );
      now = now.add(const Duration(seconds: 4));
      await expectLater(
        provider.autocomplete('par'),
        throwsA(
          isA<CityPlacesException>().having(
            (e) => e.message,
            'message',
            contains('8 seconds'),
          ),
        ),
      );
      expect(adapter.requests, hasLength(1));
      now = now.add(const Duration(seconds: 8));
      expect(adapter.requests, hasLength(1));
      adapter.status = 200;
      expect(await provider.autocomplete('cai'), isNotEmpty);
      expect(adapter.requests, hasLength(2));
    },
  );
  test(
    '429 without a usable Retry-After applies a bounded default cooldown',
    () async {
      var now = DateTime.utc(2026, 10, 28);
      provider = PhotonCityPlacesProvider(
        transport: Dio()..httpClientAdapter = adapter,
        now: () => now,
      );
      adapter.status = 429;
      adapter.headers['retry-after'] = ['not a delay'];
      await expectLater(
        provider.autocomplete('cai'),
        throwsA(
          isA<CityPlacesException>().having(
            (e) => e.message,
            'message',
            contains('30 seconds'),
          ),
        ),
      );
      await expectLater(
        provider.autocomplete('cai'),
        throwsA(isA<CityPlacesException>()),
      );
      expect(adapter.requests, hasLength(1));
      now = now.add(const Duration(seconds: 30));
      adapter.status = 200;
      expect(await provider.autocomplete('cai'), isNotEmpty);
    },
  );
  test(
    'HTTP 403 HTML is reported as denied access, not invalid GeoJSON',
    () async {
      adapter.status = 403;
      adapter.data = '<html><h1>403 Forbidden</h1><hr>nginx</html>';
      adapter.headers[Headers.contentTypeHeader] = ['text/html'];
      await expectLater(
        provider.autocomplete('cai'),
        throwsA(
          isA<CityPlacesException>().having(
            (e) => e.message,
            'message',
            contains('denied access (403)'),
          ),
        ),
      );
    },
  );
  test('malformed HTTP 200 JSON is a parsing error', () async {
    adapter.data = '<html>unexpected body</html>';
    await expectLater(
      provider.autocomplete('cai'),
      throwsA(
        isA<CityPlacesException>().having(
          (e) => e.message,
          'message',
          contains('Unable to read'),
        ),
      ),
    );
  });
  test('Dio-wrapped programming errors remain observable', () async {
    adapter.failure = DioExceptionType.unknown;
    adapter.cause = StateError('transformer bug');
    await expectLater(provider.autocomplete('cai'), throwsStateError);
  });
  test(
    'opt-in debug diagnostics omit raw input, headers and response values',
    () async {
      final messages = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) =>
          messages.add(message ?? '');
      addTearDown(() => debugPrint = original);
      provider = PhotonCityPlacesProvider(
        transport: Dio(
          BaseOptions(headers: {'Authorization': 'Bearer secret-test-token'}),
        )..httpClientAdapter = adapter,
        debugLogging: true,
      );
      await provider.autocomplete('private city text');
      final diagnostic = messages.join('\n');
      expect(diagnostic, contains('status=200'));
      expect(diagnostic, contains('FeatureCollection(features=1)'));
      expect(diagnostic, contains('parsedCities=1'));
      expect(diagnostic, isNot(contains('private city text')));
      expect(diagnostic, isNot(contains('secret-test-token')));
      expect(diagnostic, isNot(contains('Dubai')));
      expect(diagnostic, isNot(contains('55.2708')));
    },
  );
  test('diagnostics are disabled by default', () async {
    final messages = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) =>
        messages.add(message ?? '');
    addTearDown(() => debugPrint = original);
    await provider.autocomplete('cai');
    expect(messages, isEmpty);
  });
  for (final failure in [
    DioExceptionType.connectionError,
    DioExceptionType.receiveTimeout,
    DioExceptionType.connectionTimeout,
  ]) {
    test('$failure maps to safe error', () async {
      adapter.failure = failure;
      await expectLater(
        provider.autocomplete('Dub'),
        throwsA(
          isA<CityPlacesException>().having(
            (e) => e.message,
            'message',
            contains(
              failure == DioExceptionType.connectionError
                  ? 'Unable'
                  : 'timed out',
            ),
          ),
        ),
      );
    });
  }
  testWidgets(
    'whole request times out after eight seconds and cancels transport',
    (tester) async {
      adapter.pending = Completer<ResponseBody>();
      final request = provider.autocomplete('Dub');
      final expectation = expectLater(
        request,
        throwsA(
          isA<CityPlacesException>().having(
            (e) => e.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 8));
      await expectation;
      expect(adapter.requests.single.cancelToken!.isCancelled, true);
    },
  );
  test(
    'too-short and over-limit text make no requests; concurrent identical queries coalesce',
    () async {
      expect(await provider.autocomplete('D'), isEmpty);
      expect(await provider.autocomplete('x' * 121), isEmpty);
      final one = provider.autocomplete('Dub');
      final two = provider.autocomplete(' Dub ');
      await Future.wait([one, two]);
      expect(adapter.requests.length, 1);
      expect((await provider.autocomplete('Dub')).length, 1);
      expect(adapter.requests.length, 2);
    },
  );
  test('at most six valid suggestions are presented', () {
    expect(
      PhotonCityPlacesProvider.parse(
        photonCollection(List.generate(10, (i) => photonFeature(id: i + 1))),
      ).length,
      6,
    );
  });
}
