import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';
import 'package:travibe/features/profile/data/profile_repo.dart';
import 'package:travibe/features/search/data/search_repo.dart';

class Api extends ApiService {
  String? path;
  Map<String, dynamic>? body;
  dynamic response;
  @override
  Future<dynamic> delete(String endpoint) async {
    path = endpoint;
    return response;
  }

  @override
  Future<dynamic> post(String endpoint, Map<String, dynamic> data) async {
    path = endpoint;
    body = data;
    return response;
  }

  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
    path = endpoint;
    body = queryParameters;
    return response;
  }
}

void main() {
  test(
    'remove follower uses confirmed DELETE and validates success body',
    () async {
      final api = Api()..response = {'message': 'Follower removed.'};
      final repo = FollowRepo(apiService: api);
      await repo.removeFollower('23');
      expect(api.path, 'users/23/follower');
      api.response = null;
      await expectLater(repo.removeFollower('23'), throwsA(isA<ApiError>()));
    },
  );
  test('user report reuses confirmed report schema and reason enums', () async {
    final api = Api()
      ..response = {
        'data': {'id': 9},
      };
    await ProfileRepo(apiService: api).reportUser('23', 'harassment');
    expect(api.path, 'reports');
    expect(api.body, {'type': 'user', 'id': 23, 'reason': 'harassment'});
  });
  test('follows_you remains independent of is_following in public users', () {
    final user = PublicUserModel.fromJson({
      'id': 23,
      'is_following': true,
      'follows_you': false,
    });
    expect(user.isFollowing, true);
    expect(user.followsYou, false);
    expect(user.copyWith(followsYou: true).isFollowing, true);
  });
  test(
    'successful empty search differs from malformed identity/name entries',
    () async {
      final api = Api()
        ..response = {
          'data': [],
          'meta': {'current_page': 1, 'last_page': 1, 'total': 0},
        };
      final repo = SearchRepo(apiService: api);
      expect((await repo.searchUsers('trav')).users, isEmpty);
      for (final entry in [
        <String, dynamic>{'name': 'No ID'},
        <String, dynamic>{'id': 23},
      ]) {
        api.response = {
          'data': [entry],
          'meta': {'current_page': 1, 'last_page': 1, 'total': 1},
        };
        await expectLater(repo.searchUsers('trav'), throwsA(isA<ApiError>()));
      }
    },
  );
}
