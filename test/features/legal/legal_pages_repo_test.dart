import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/legal/data/legal_page.dart';
import 'package:travibe/features/legal/data/legal_pages_repo.dart';

import 'legal_html_parser_test.dart' show websiteTerms;

class HtmlAdapter implements HttpClientAdapter {
  String body = websiteTerms;
  int status = 200;
  DioExceptionType? failure;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (failure != null) {
      throw DioException(requestOptions: options, type: failure!);
    }
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: ['text/html; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late HtmlAdapter adapter;
  late LegalPagesRepo repo;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    adapter = HtmlAdapter();
    repo = LegalPagesRepo(transport: Dio()..httpClientAdapter = adapter);
  });

  test('fetches the public website page and caches it', () async {
    expect(await repo.cached(LegalPageSlug.terms), isNull);
    final page = await repo.fetch(LegalPageSlug.terms);
    expect(
      adapter.requests.single.uri,
      Uri.parse('https://travibeapp.com/terms'),
    );
    expect(adapter.requests.single.headers['Accept'], 'text/html');
    expect(adapter.requests.single.headers.containsKey('Authorization'), false);
    expect(page.title, 'Terms of Service');

    final cached = await repo.cached(LegalPageSlug.terms);
    expect(cached?.title, 'Terms of Service');
    expect(cached?.updatedAt, DateTime(2026, 11, 25));
    expect(cached?.blocks.length, page.blocks.length);
    expect(await repo.cached(LegalPageSlug.privacy), isNull);
  });

  test('privacy uses its own URL and cache key', () async {
    await repo.fetch(LegalPageSlug.privacy);
    expect(adapter.requests.single.uri.path, '/privacy');
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.containsKey(LegalPagesRepo.cacheKey(LegalPageSlug.privacy)),
      true,
    );
    expect(
      prefs.containsKey(LegalPagesRepo.cacheKey(LegalPageSlug.terms)),
      false,
    );
  });

  test('a corrupt or mismatched cache counts as no cache', () async {
    SharedPreferences.setMockInitialValues({
      LegalPagesRepo.cacheKey(LegalPageSlug.terms): '{not json',
      LegalPagesRepo.cacheKey(LegalPageSlug.privacy):
          '{"slug":"terms","title":"T","blocks":[{"s":[{"t":"x"}]}]}',
    });
    expect(await repo.cached(LegalPageSlug.terms), isNull);
    expect(await repo.cached(LegalPageSlug.privacy), isNull);
  });

  test('offline is an ApiError and keeps the previous cache', () async {
    await repo.fetch(LegalPageSlug.terms);
    adapter.failure = DioExceptionType.connectionError;
    await expectLater(
      repo.fetch(LegalPageSlug.terms),
      throwsA(isA<ApiError>()),
    );
    expect((await repo.cached(LegalPageSlug.terms))?.title, 'Terms of Service');
  });

  test('an HTTP error or unreadable markup is an ApiError', () async {
    adapter.status = 503;
    await expectLater(
      repo.fetch(LegalPageSlug.terms),
      throwsA(isA<ApiError>()),
    );
    adapter
      ..status = 200
      ..body = '<html><body>Maintenance</body></html>';
    await expectLater(
      repo.fetch(LegalPageSlug.terms),
      throwsA(isA<ApiError>()),
    );
    expect(await repo.cached(LegalPageSlug.terms), isNull);
  });
}
