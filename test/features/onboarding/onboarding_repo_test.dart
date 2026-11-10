import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/onboarding/data/models/app_locale.dart';
import 'package:travibe/features/onboarding/data/models/onboarding_model.dart';
import 'package:travibe/features/onboarding/data/onboarding_repo.dart';
import 'onboarding_fixtures.dart';

class PublicAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Future<ResponseBody> Function(RequestOptions) handler = (_) async =>
      publicResponse(slideJson());
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody publicResponse(
  dynamic data, {
  int status = 200,
  Map<String, List<String>> headers = const {},
}) => ResponseBody.fromString(
  status == 304 ? '' : jsonEncode(data),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
    ...headers,
  },
);

void main() {
  test(
    'slides parse server order/copy, optional remote asset, and matching local artwork',
    () {
      final json = slideJson();
      (json['data'] as List).insert(0, {
        'key': 'new',
        'title': 'New content',
        'body': 'New body',
        'asset_url': 'https://example.invalid/art.png',
      });
      final slides = OnboardingModel.parse(json);
      expect(slides.first.key, 'new');
      expect(slides.first.assetUrl, 'https://example.invalid/art.png');
      expect(slides.first.localImage, isNull);
      expect(slides[1].localImage, 'assets/images/onboarding/on1.png');
      expect(slides[1].title, 'Discover places from the server');
    },
  );
  test('malformed/empty/duplicate slides are rejected', () {
    for (final json in [
      null,
      {'data': []},
      {
        'data': [
          {'key': 'x'},
        ],
      },
      {
        'data': [
          (slideJson()['data'] as List).first,
          (slideJson()['data'] as List).first,
        ],
      },
    ]) {
      expect(() => OnboardingModel.parse(json), throwsFormatException);
    }
  });
  test('locales parse actual nested shape, names, default, and RTL', () {
    final catalog = LocaleCatalog.parse(localesJson());
    expect(catalog.defaultCode, 'en');
    expect(catalog.locales[1].name, 'العربية');
    expect(catalog.locales[1].rtl, true);
    expect(catalog.locales.every((locale) => locale.supported), true);
    expect(
      () => LocaleCatalog.parse({
        'data': {'locales': [], 'default': 'en'},
      }),
      throwsFormatException,
    );
  });
  test(
    'public requests have no bearer token, cache max-age, revalidate with ETag/304',
    () async {
      var now = DateTime(2026, 11, 3);
      final adapter = PublicAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final repo = OnboardingRepo(transport: dio, now: () => now);
      adapter.handler = (_) async => publicResponse(
        slideJson(),
        headers: {
          'etag': ['"v1"'],
          'cache-control': ['public, max-age=86400'],
        },
      );
      final first = await repo.slides('en');
      expect(adapter.requests.single.headers['Authorization'], isNull);
      expect(adapter.requests.single.headers['Accept-Language'], 'en');
      expect(identical(await repo.slides('en'), first), true);
      expect(adapter.requests.length, 1);
      now = now.add(const Duration(days: 1));
      adapter.handler = (request) async {
        expect(request.headers['If-None-Match'], '"v1"');
        return publicResponse(
          null,
          status: 304,
          headers: {
            'cache-control': ['public, max-age=86400'],
          },
        );
      };
      expect(identical(await repo.slides('en'), first), true);
      expect(adapter.requests.length, 2);
      await repo.slides('en');
      expect(adapter.requests.length, 2);
    },
  );
  test(
    'prefetch coalesces concurrent public requests and keeps locales separate',
    () async {
      final adapter = PublicAdapter();
      final gate = Completer<void>();
      adapter.handler = (request) async {
        await gate.future;
        return publicResponse(
          request.path == 'locales' ? localesJson() : slideJson(),
          headers: {
            'cache-control': ['max-age=60'],
          },
        );
      };
      final repo = OnboardingRepo(
        transport: Dio()..httpClientAdapter = adapter,
      );
      final a = repo.prefetch('en');
      final b = repo.prefetch('en');
      gate.complete();
      await Future.wait([a, b]);
      expect(adapter.requests.length, 2);
      await repo.slides('ar');
      expect(adapter.requests.last.headers['Accept-Language'], 'ar');
      expect(adapter.requests.length, 3);
    },
  );
  test(
    'no-store and malformed responses are not cached; failure supports retry',
    () async {
      final adapter = PublicAdapter();
      final repo = OnboardingRepo(
        transport: Dio()..httpClientAdapter = adapter,
      );
      adapter.handler = (_) async => publicResponse(
        {'data': []},
        headers: {
          'cache-control': ['max-age=86400'],
        },
      );
      await expectLater(repo.slides('en'), throwsA(isA<ApiError>()));
      adapter.handler = (_) async => publicResponse(
        slideJson(),
        headers: {
          'cache-control': ['no-store'],
        },
      );
      await repo.slides('en');
      await repo.slides('en');
      expect(adapter.requests.length, 3);
      adapter.handler = (_) async =>
          publicResponse({'message': 'Unavailable'}, status: 503);
      await expectLater(repo.slides('en'), throwsA(isA<ApiError>()));
      adapter.handler = (_) async => publicResponse(slideJson());
      expect(await repo.slides('en'), hasLength(3));
    },
  );
  test(
    'receive timeout coalesces pending requests and explicit retry starts fresh',
    () async {
      final adapter = PublicAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final repo = OnboardingRepo(transport: dio);
      final gate = Completer<ResponseBody>();
      final entered = Completer<RequestOptions>();
      adapter.handler = (options) {
        entered.complete(options);
        return gate.future;
      };
      final first = repo.slides('en'), second = repo.slides('en');
      final failure = expectLater(
        Future.wait([first, second]),
        throwsA(isA<ApiError>()),
      );
      final options = await entered.future;
      gate.completeError(
        DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
        ),
      );
      await failure;
      expect(adapter.requests, hasLength(1));
      adapter.handler = (_) async => publicResponse(slideJson());
      expect(await repo.slides('en'), hasLength(3));
      expect(adapter.requests, hasLength(2));
    },
  );
  for (final status in [401, 403, 404, 500, 503]) {
    test(
      'HTTP $status is a recoverable public content failure, not cached',
      () async {
        final adapter = PublicAdapter()
          ..handler = (_) async =>
              publicResponse({'message': 'Unavailable'}, status: status);
        final repo = OnboardingRepo(
          transport: Dio()..httpClientAdapter = adapter,
        );
        await expectLater(
          repo.slides('en'),
          throwsA(
            isA<ApiError>().having((e) => e.statusCode, 'status', status),
          ),
        );
        adapter.handler = (_) async => publicResponse(slideJson());
        expect(await repo.slides('en'), hasLength(3));
        expect(adapter.requests, hasLength(2));
      },
    );
  }
  test('invalid JSON is handled and a later valid response can load', () async {
    final adapter = PublicAdapter()
      ..handler = (_) async => ResponseBody.fromString(
        '{invalid JSON',
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    final repo = OnboardingRepo(transport: Dio()..httpClientAdapter = adapter);
    await expectLater(repo.slides('en'), throwsA(isA<ApiError>()));
    adapter.handler = (_) async => publicResponse(slideJson());
    expect(await repo.slides('en'), hasLength(3));
  });
}
