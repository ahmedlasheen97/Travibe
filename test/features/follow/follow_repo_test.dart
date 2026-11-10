import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';

class FakeApi extends ApiService {
  String? path;
  Map<String, dynamic>? payload;
  dynamic response;
  ApiError? error;
  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
    path = endpoint;
    payload = queryParameters;
    if (error != null) throw error!;
    return response;
  }

  @override
  Future<dynamic> post(String endpoint, Map<String, dynamic> data) async {
    path = endpoint;
    payload = data;
    if (error != null) throw error!;
    return response;
  }
}

void main() {
  late FakeApi api;
  late FollowRepo repo;
  setUp(() {
    api = FakeApi();
    repo = FollowRepo(apiService: api);
  });

  for (final following in [true, false]) {
    test(
      'documented ${following ? 'follow' : 'unfollow'} payload and response',
      () async {
        api.response = {
          'message': 'Done',
          'data': {
            'id': 7,
            'is_following': following.toString(),
            'followers_count': 12,
          },
        };
        final result = await repo.setFollowing('7', following);
        expect(api.path, 'users/7/${following ? 'follow' : 'unfollow'}');
        expect(api.payload, isEmpty);
        expect(result.isFollowing, following);
        expect(result.followersCount, 12);
      },
    );
  }
  test('status uses boolean check endpoint', () async {
    api.response = {
      'data': {'user_id': 7, 'is_following': true},
    };
    final result = await repo.status('7');
    expect(api.path, 'users/7/following');
    expect(result.userId, '7');
    expect(result.isFollowing, isTrue);
  });
  test('status rejects mismatched user and invalid boolean', () async {
    api.response = {
      'data': {'user_id': 8, 'is_following': true},
    };
    await expectLater(repo.status('7'), throwsA(isA<ApiError>()));
    api.response = {
      'data': {'user_id': 7, 'is_following': 'true'},
    };
    await expectLater(repo.status('7'), throwsA(isA<ApiError>()));
  });
  for (final type in FollowListType.values) {
    test('${type.name} has documented path and pagination', () async {
      api.response = {
        'data': [
          {'id': 7},
        ],
        'meta': {'current_page': 2, 'last_page': 3, 'total': 31},
      };
      final result = await repo.users(
        type: type,
        userId: '7',
        page: 2,
        perPage: 20,
      );
      expect(api.path, switch (type) {
        FollowListType.suggested => 'users/suggested',
        FollowListType.followers => 'users/7/followers',
        FollowListType.following => 'users/7/following-list',
      });
      expect(api.payload, {'page': 2, 'per_page': 20});
      expect(result.users.single.id, '7');
      expect(result.hasMore, isTrue);
    });
  }
  test('preserves backend errors from mutations, status and lists', () async {
    final error = ApiError(message: 'Forbidden', statusCode: 403);
    api.error = error;
    await expectLater(repo.setFollowing('7', true), throwsA(same(error)));
    await expectLater(repo.status('7'), throwsA(same(error)));
    await expectLater(
      repo.users(type: FollowListType.suggested),
      throwsA(same(error)),
    );
  });
  test(
    'rejects invalid pagination and missing list user before network',
    () async {
      await expectLater(
        repo.users(type: FollowListType.followers),
        throwsArgumentError,
      );
      await expectLater(
        repo.users(type: FollowListType.suggested, perPage: 101),
        throwsArgumentError,
      );
      expect(api.path, isNull);
    },
  );
}
