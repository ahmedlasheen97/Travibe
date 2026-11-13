import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/search/data/users_page_model.dart';

enum FollowListType { suggested, followers, following }

class FollowStatus {
  const FollowStatus({
    required this.userId,
    required this.isFollowing,
    this.followRequested = false,
  });
  final String userId;
  final bool isFollowing;

  /// A pending request to a private account.
  final bool followRequested;

  factory FollowStatus.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    if (data is! Map ||
        data['user_id'] is! int ||
        data['is_following'] is! bool) {
      throw ApiError(message: 'Invalid follow status response');
    }
    return FollowStatus(
      userId: data['user_id'].toString(),
      isFollowing: data['is_following'] as bool,
      followRequested: data['follow_requested'] == true,
    );
  }
}

class FollowRepo {
  FollowRepo({ApiService? apiService}) : _api = apiService ?? ApiService();
  final ApiService _api;

  String _id(String id) {
    final value = int.tryParse(id);
    if (value == null) throw ArgumentError.value(id, 'userId');
    return value.toString();
  }

  Future<PublicUserModel> setFollowing(String userId, bool following) async {
    final response = await _api.post(
      'users/${_id(userId)}/${following ? 'follow' : 'unfollow'}',
      {},
    );
    if (response is! Map<String, dynamic> || response['data'] is! Map) {
      throw ApiError(message: 'Invalid follow response');
    }
    return PublicUserModel.fromJson(
      Map<String, dynamic>.from(response['data']),
    );
  }

  Future<void> removeFollower(String userId) async {
    final response = await _api.delete('users/${_id(userId)}/follower');
    if (response is! Map || response['message'] is! String) {
      throw ApiError(
        message: 'The server did not confirm follower removal. Please refresh.',
      );
    }
  }

  Future<FollowStatus> status(String userId) async {
    final response = await _api.get('users/${_id(userId)}/following');
    if (response is! Map<String, dynamic>) {
      throw ApiError(message: 'Invalid follow status response');
    }
    final status = FollowStatus.fromJson(response);
    if (status.userId != _id(userId)) {
      throw ApiError(message: 'Follow status returned a different user');
    }
    return status;
  }

  Future<UsersPageModel> users({
    required FollowListType type,
    String? userId,
    int page = 1,
    int perPage = 15,
  }) async {
    if (page < 1 || perPage < 1 || perPage > 100) {
      throw ArgumentError('Invalid follow pagination');
    }
    final path = type == FollowListType.suggested
        ? 'users/suggested'
        : 'users/${_id(userId ?? '')}/${type == FollowListType.followers ? 'followers' : 'following-list'}';
    final response = await _api.get(
      path,
      queryParameters: {'page': page, 'per_page': perPage},
    );
    if (response is! Map<String, dynamic> ||
        response['data'] is! List ||
        response['meta'] is! Map) {
      throw ApiError(message: 'Invalid user list response');
    }
    return UsersPageModel.fromJson(response);
  }
}
