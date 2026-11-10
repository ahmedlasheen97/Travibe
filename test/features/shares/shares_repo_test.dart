import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/shares/data/share_model.dart';
import 'package:travibe/features/shares/data/shares_repo.dart';
import 'fixtures.dart';

class ShareApi extends ApiService {
  final List<String> calls = [];
  Map<String, dynamic>? body;
  Map<String, dynamic>? query;
  dynamic response;
  ApiError? error;
  dynamic result(String call) {
    calls.add(call);
    if (error != null) throw error!;
    return response;
  }

  @override
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    query = queryParameters;
    return result('GET $path');
  }

  @override
  Future<dynamic> post(String path, Map<String, dynamic> data) async {
    body = data;
    return result('POST $path');
  }

  @override
  Future<dynamic> delete(String path) async => result('DELETE $path');
}

void main() {
  test(
    'platform values match the documented enum, not the response type placeholder',
    () {
      final api =
          jsonDecode(File('docs/openapi.json').readAsStringSync()) as Map;
      final documented = api['components']['schemas']['SharePlatform']['enum'];
      expect(
        SharePlatform.values.map((value) => value.value).toList(),
        documented,
      );
      expect(
        () => ShareModel.fromJson({...shareJson(), 'platform': 'string'}),
        throwsA(isA<ApiError>()),
      );
    },
  );

  test(
    'plain internal repost sends null comment and parses the confirmed minimal response',
    () async {
      final api = ShareApi()
        ..response = {
          'data': {
            'id': 1,
            'user_id': 1,
            'post_id': 10,
            'comment': null,
            'platform': 'internal',
            'repost': {'id': 99, 'type': 'repost'},
          },
        };
      final share = await SharesRepo(
        apiService: api,
      ).create(10, const CreateShareRequest());
      expect(api.calls, ['POST posts/10/shares']);
      expect(api.body, {'platform': 'internal', 'comment': null});
      expect(share.id, 1);
      expect(share.postId, 10);
      expect(share.repost!.id, '99');
      expect(share.comment, isNull);
    },
  );

  test(
    'request serializes documented platform and optional trimmed comment',
    () {
      expect(const CreateShareRequest().toJson(), {
        'platform': 'internal',
        'comment': null,
      });
      expect(const CreateShareRequest(comment: '  ').toJson(), {
        'platform': 'internal',
        'comment': null,
      });
      expect(const CreateShareRequest(comment: ' Note ').toJson(), {
        'platform': 'internal',
        'comment': 'Note',
      });
      expect(
        const CreateShareRequest(platform: SharePlatform.copyLink).toJson(),
        {'platform': 'copy_link', 'comment': null},
      );
      expect(CreateShareRequest(comment: '😀' * 500).validationError, isNull);
      expect(
        () => CreateShareRequest(comment: '😀' * 501).toJson(),
        throwsA(isA<ApiError>()),
      );
    },
  );
  test('create parses wrapper, reliable share ID, owner and repost', () async {
    final api = ShareApi()
      ..response = {
        'data': {
          ...shareJson(comment: 'Note'),
          'repost': {
            'id': 99,
            'type': 'quote',
            'original_post': {'id': 10},
          },
        },
      };
    final result = await SharesRepo(
      apiService: api,
    ).create(10, const CreateShareRequest(comment: 'Note'));
    expect(api.calls, ['POST posts/10/shares']);
    expect(api.body, {'platform': 'internal', 'comment': 'Note'});
    expect(result.id, 73);
    expect(result.postId, 10);
    expect(result.userId, 7);
    expect(result.repost!.id, '99');
    expect(result.repost!.originalPost!.id, '10');
  });
  test(
    'delete uses share ID independently of post ID and only needs success',
    () async {
      final api = ShareApi()..response = {'message': 'Share removed'};
      await SharesRepo(apiService: api).delete(10, 73);
      expect(api.calls, ['DELETE posts/10/shares/73']);
    },
  );
  test('GET shares parses resources, empty pages and pagination', () async {
    final api = ShareApi()
      ..response = {
        'data': [shareJson()],
        'meta': {'current_page': 2, 'last_page': 3, 'total': 25},
        'links': {'next': 'next'},
      };
    final repo = SharesRepo(apiService: api);
    final page = await repo.list(10, page: 2, perPage: 10);
    expect(api.calls.single, 'GET posts/10/shares');
    expect(api.query, {'page': 2, 'per_page': 10});
    expect(page.hasMore, isTrue);
    expect(page.total, 25);
    api.response = {
      'data': [],
      'meta': {'current_page': 1, 'last_page': 1, 'total': 0},
    };
    final empty = await repo.list(10);
    expect(empty.shares, isEmpty);
    expect(empty.hasMore, isFalse);
  });
  test('count is read from PostResource, not share list total', () async {
    final api = ShareApi()
      ..response = {
        'data': {'id': 10, 'shares_count': 5},
      };
    expect(await SharesRepo(apiService: api).count(10), 5);
    expect(api.calls, ['GET posts/10']);
    api.response = {
      'data': {'id': 10},
    };
    await expectLater(
      SharesRepo(apiService: api).count(10),
      throwsA(isA<ApiError>()),
    );
  });
  test(
    'missing and invalid IDs are rejected instead of using the post ID',
    () async {
      for (final id in [null, '73', 0, -1]) {
        expect(
          () => ShareModel.fromJson({...shareJson(), 'id': id}),
          throwsA(isA<ApiError>()),
        );
      }
      final api = ShareApi();
      await expectLater(
        SharesRepo(apiService: api).delete(10, 0),
        throwsA(isA<ApiError>()),
      );
      expect(api.calls, isEmpty);
    },
  );
  test('malformed metadata and wrong resource post are rejected', () async {
    final api = ShareApi()
      ..response = {
        'data': [],
        'meta': {'total': 0},
      };
    final repo = SharesRepo(apiService: api);
    await expectLater(repo.list(10), throwsA(isA<ApiError>()));
    api.response = {'data': shareJson(postId: 11)};
    await expectLater(
      repo.create(10, const CreateShareRequest()),
      throwsA(isA<ApiError>()),
    );
  });
  test('API failures preserve clean messages and HTTP status', () async {
    final error = ApiError(message: 'Unauthenticated', statusCode: 401);
    final api = ShareApi()..error = error;
    await expectLater(
      SharesRepo(apiService: api).list(10),
      throwsA(same(error)),
    );
  });
}
