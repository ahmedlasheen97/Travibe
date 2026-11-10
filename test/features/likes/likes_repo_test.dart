import '../../helpers/cursor_fixtures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/likes/cubit/likes_users_cubit.dart';
import 'package:travibe/core/cubit/cursor_list_cubit.dart';
import 'package:travibe/features/likes/data/like_model.dart';
import 'package:travibe/features/likes/data/likes_repo.dart';

class LikesApi extends ApiService {
  final List<String> calls = [];
  Map<String, dynamic>? query;
  dynamic response = {'is_liked': true, 'likes_count': 3, 'message': 'Liked'};
  ApiError? error;
  dynamic result(String call) {
    calls.add(call);
    if (error != null) throw error!;
    return response;
  }

  @override
  Future<dynamic> post(String endpoint, Map<String, dynamic> data) async {
    expect(data, isEmpty);
    return result('POST $endpoint');
  }

  @override
  Future<dynamic> delete(String endpoint) async => result('DELETE $endpoint');
  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
    query = queryParameters;
    return result('GET $endpoint');
  }
}

void main() {
  for (final target in [
    const LikeTarget.post(10),
    const LikeTarget.comment(10, 2),
  ]) {
    test(
      'verified mutation routes and top-level response: ${target.path}',
      () async {
        final api = LikesApi();
        final repo = LikesRepo(apiService: api);
        final result = await repo.setLiked(target, true);
        expect(result!.isLiked, isTrue);
        expect(result.count, 3);
        api.response = {
          'is_liked': false,
          'likes_count': 2,
          'message': 'Unliked',
        };
        expect((await repo.setLiked(target, false))!.isLiked, isFalse);
        expect(api.calls, [
          'POST ${target.path}/like',
          'DELETE ${target.path}/like',
        ]);
      },
    );
    test(
      'likes list parses public users and pagination: ${target.path}',
      () async {
        final api = LikesApi()
          ..response = {
            'data': [
              {
                'id': 7,
                'name': 'Sara',
                'username': 'sara',
                'is_following': true,
              },
            ],
            'meta': cursorEnvelope(next: 'older|opaque==')['meta'],
            'links': {'next': 'next'},
          };
        final page = await LikesRepo(
          apiService: api,
        ).list(target, cursor: 'next/+opaque==', perPage: 10);
        expect(api.calls, ['GET ${target.path}/likes']);
        expect(api.query, {'cursor': 'next/+opaque==', 'per_page': 10});
        expect(page.items.single.handle, '@sara');
        expect(page.items.single.isFollowing, isTrue);
        expect(page.hasMore, isTrue);
        expect(page.pagination.nextCursor, 'older|opaque==');
      },
    );
  }
  test('malformed or nested mutation responses are rejected', () {
    for (final value in [
      null,
      {
        'data': {'is_liked': true, 'likes_count': 1},
      },
      {'likes_count': 5},
      {'is_liked': true, 'likes_count': -1},
      {'is_liked': 'true', 'likes_count': 1},
    ]) {
      expect(() => LikeValue.fromJson(value), throwsA(isA<ApiError>()));
    }
  });
  test(
    'state-less success uses documented resource for reconciliation',
    () async {
      final api = LikesApi()..response = {'message': 'Liked'};
      final repo = LikesRepo(apiService: api);
      const target = LikeTarget.comment(10, 2);
      expect(await repo.setLiked(target, true), isNull);
      api.response = {
        'data': {'is_liked': true, 'likes_count': 4},
      };
      final result = await repo.getState(target);
      expect(result.isLiked, isTrue);
      expect(result.count, 4);
      expect(api.calls, [
        'POST posts/10/comments/2/like',
        'GET posts/10/comments/2',
      ]);
    },
  );
  test(
    'list handles loading, API failure, retry and empty results with existing Cubit',
    () async {
      final error = ApiError(message: 'Forbidden', statusCode: 403);
      final api = LikesApi()..error = error;
      final repo = LikesRepo(apiService: api);
      final cubit = LikesUsersCubit(
        target: const LikeTarget.post(10),
        repo: repo,
      );
      addTearDown(cubit.close);
      final request = cubit.load();
      expect(cubit.state.status, CursorListStatus.loading);
      await request;
      expect(cubit.state.error, same(error));
      api.error = null;
      api.response = {'data': [], 'meta': cursorEnvelope()['meta']};
      await cubit.load();
      expect(cubit.state.status, CursorListStatus.loaded);
      expect(cubit.state.items, isEmpty);
      expect(cubit.state.hasMore, isFalse);
    },
  );
  test(
    'missing list metadata fails without manufacturing an empty result',
    () async {
      final api = LikesApi()..response = {'data': []};
      await expectLater(
        LikesRepo(apiService: api).list(const LikeTarget.post(10)),
        throwsA(isA<ApiError>()),
      );
    },
  );
}
