import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/search/data/users_page_model.dart';

class BlockStatus {
  const BlockStatus({required this.userId, required this.isBlocked});
  final String userId;
  final bool isBlocked;
}

class BlockRepo {
  BlockRepo({ApiService? apiService}) : _api = apiService ?? ApiService();
  final ApiService _api;

  String _id(String id) {
    final value = int.tryParse(id);
    if (value == null) throw ArgumentError.value(id, 'userId');
    return value.toString();
  }

  Future<PublicUserModel> setBlocked(String userId, bool blocked) async {
    final id = _id(userId);
    final response = await _api.post(
      'users/$id/${blocked ? 'block' : 'unblock'}',
      {},
    );
    if (response is! Map ||
        response['data'] is! Map ||
        response['message'] is! String) {
      throw ApiError(message: 'Invalid block response');
    }
    final data = Map<String, dynamic>.from(response['data']);
    final flag = data['is_blocked'];
    if (!['true', 'false', '1', '0', true, false, 1, 0].contains(flag)) {
      throw ApiError(message: 'Invalid block response');
    }
    final user = PublicUserModel.fromJson(data);
    if (user.id != id || user.isBlocked != blocked) {
      throw ApiError(
        message: 'The server did not confirm the requested block state',
      );
    }
    return user;
  }

  Future<BlockStatus> status(String userId) async {
    final id = _id(userId);
    final response = await _api.get('users/$id/block');
    final data = response is Map ? response['data'] : null;
    if (data is! Map ||
        data['user_id'] is! int ||
        data['user_id'].toString() != id ||
        data['is_blocked'] is! bool) {
      throw ApiError(message: 'Invalid block status response');
    }
    return BlockStatus(userId: id, isBlocked: data['is_blocked'] as bool);
  }

  Future<UsersPageModel> users({int page = 1, int perPage = 15}) async {
    if (page < 1 || perPage < 1 || perPage > 100) {
      throw ArgumentError('Invalid blocked-user pagination');
    }
    final response = await _api.get(
      'me/blocks',
      queryParameters: {'page': page, 'per_page': perPage},
    );
    if (response is! Map<String, dynamic> ||
        response['data'] is! List ||
        response['meta'] is! Map) {
      throw ApiError(message: 'Invalid blocked-user list');
    }
    return UsersPageModel.fromJson(response);
  }
}
