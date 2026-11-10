import '../../helpers/cursor_fixtures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/home/data/posts_repo.dart';

class FakeApiService extends ApiService {
  String? endpoint;
  Map<String, dynamic>? query;
  Object? error;
  dynamic response = {
    'data': [
      {'id': 7, 'content': 'Hello'},
    ],
    'links': {'first': null, 'last': null, 'prev': null, 'next': null},
    'meta': cursorEnvelope(next: 'older|opaque==')['meta'],
  };

  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
    this.endpoint = endpoint;
    query = queryParameters;
    if (error != null) throw error!;
    return response;
  }
}

void main() {
  for (final feed in FeedType.values) {
    test(
      '${feed.name} uses documented path and pagination and parses posts',
      () async {
        final api = FakeApiService();
        final repo = PostsRepo(apiService: api);
        final result = await repo.getPosts(
          feed: feed,
          cursor: 'next/+opaque==',
          perPage: 20,
        );
        expect(api.endpoint, 'feed/${feed.name}');
        expect(api.query, {'cursor': 'next/+opaque==', 'per_page': 20});
        expect(result.posts.single.id, '7');
        expect(result.pagination!.nextCursor, 'older|opaque==');
        expect(result.hasMore, isTrue);
      },
    );
  }

  test('preserves ApiError identity including status', () async {
    final api = FakeApiService();
    final error = ApiError(message: 'Unauthenticated', statusCode: 401);
    api.error = error;
    expect(PostsRepo(apiService: api).getPosts(), throwsA(same(error)));
  });

  test('malformed response is an error rather than an empty feed', () async {
    final api = FakeApiService()..response = {'data': null};
    expect(PostsRepo(apiService: api).getPosts(), throwsA(isA<ApiError>()));
  });

  test('rejects unsupported pagination before sending a request', () async {
    final api = FakeApiService();
    final repo = PostsRepo(apiService: api);
    for (final size in [0, 101]) {
      await expectLater(repo.getPosts(perPage: size), throwsArgumentError);
    }
    await expectLater(repo.getPosts(cursor: ''), throwsArgumentError);
    expect(api.endpoint, isNull);
  });
}
