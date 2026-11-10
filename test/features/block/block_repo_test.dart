import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/block/data/block_repo.dart';

class Api extends ApiService {
  String? method;
  String? path;
  Map<String, dynamic>? params;
  dynamic response;
  ApiError? error;
  @override
  Future<dynamic> post(String endpoint, Map<String, dynamic> data) async {
    method = 'POST';
    path = endpoint;
    params = data;
    if (error != null) throw error!;
    return response;
  }

  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
    method = 'GET';
    path = endpoint;
    params = queryParameters;
    if (error != null) throw error!;
    return response;
  }
}

void main() {
  late Api api;
  late BlockRepo repo;
  setUp(() {
    api = Api();
    repo = BlockRepo(apiService: api);
  });
  for (final blocked in [true, false]) {
    test(
      '${blocked ? 'block' : 'unblock'} uses POST and preserves existing follows',
      () async {
        api.response = {
          'message': 'Done',
          'data': {
            'id': 7,
            'is_blocked': blocked.toString(),
            'is_following': 'true',
            'followers_count': 12,
          },
        };
        final result = await repo.setBlocked('7', blocked);
        expect(api.method, 'POST');
        expect(api.path, 'users/7/${blocked ? 'block' : 'unblock'}');
        expect(api.params, isEmpty);
        expect(result.isBlocked, blocked);
        expect(result.isFollowing, isTrue);
        expect(result.followersCount, 12);
      },
    );
  }
  test('status uses documented endpoint and boolean response', () async {
    api.response = {
      'data': {'user_id': 7, 'is_blocked': true},
    };
    final result = await repo.status('7');
    expect(api.path, 'users/7/block');
    expect(api.method, 'GET');
    expect(result.isBlocked, isTrue);
  });
  test('list uses /me/blocks and documented pagination', () async {
    api.response = {
      'data': [
        {'id': 7, 'is_following': 'true'},
      ],
      'meta': {'current_page': 2, 'last_page': 3, 'total': 31},
    };
    final result = await repo.users(page: 2, perPage: 20);
    expect(api.path, 'me/blocks');
    expect(api.params, {'page': 2, 'per_page': 20});
    expect(result.users.single.isFollowing, isTrue);
    expect(result.hasMore, isTrue);
  });
  test('malformed and mismatched confirmations are rejected', () async {
    for (final data in [
      {'id': 8, 'is_blocked': 'true'},
      {'id': 7, 'is_blocked': 'false'},
      {'id': 7, 'is_blocked': 'unknown'},
    ]) {
      api.response = {'message': 'Done', 'data': data};
      await expectLater(repo.setBlocked('7', true), throwsA(isA<ApiError>()));
    }
    api.response = {
      'data': {'user_id': 8, 'is_blocked': true},
    };
    await expectLater(repo.status('7'), throwsA(isA<ApiError>()));
  });
  test(
    'backend status codes and messages are preserved for all operations',
    () async {
      final error = ApiError(message: 'Cannot block yourself', statusCode: 422);
      api.error = error;
      await expectLater(repo.setBlocked('7', true), throwsA(same(error)));
      await expectLater(repo.setBlocked('7', false), throwsA(same(error)));
      await expectLater(repo.status('7'), throwsA(same(error)));
      await expectLater(repo.users(), throwsA(same(error)));
    },
  );
  test('invalid pagination/IDs do not issue network requests', () async {
    await expectLater(repo.users(perPage: 101), throwsArgumentError);
    await expectLater(repo.users(page: 0), throwsArgumentError);
    await expectLater(repo.setBlocked('invalid', true), throwsArgumentError);
    expect(api.path, isNull);
  });
}
