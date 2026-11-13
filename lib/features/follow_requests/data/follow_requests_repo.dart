import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/search/data/users_page_model.dart';

/// Incoming follow requests to the signed-in (private) account.
class FollowRequestsRepo {
  FollowRequestsRepo({ApiService? apiService})
    : _api = apiService ?? ApiService();
  final ApiService _api;

  String _id(String id) {
    final value = int.tryParse(id);
    if (value == null || value < 1) throw ArgumentError.value(id, 'userId');
    return value.toString();
  }

  /// `GET follow-requests`, page-paginated, most recent first.
  Future<UsersPageModel> list({int page = 1, int perPage = 15}) async {
    if (page < 1 || perPage < 1 || perPage > 100) {
      throw ArgumentError('Invalid follow request pagination');
    }
    final response = await _api.get(
      'follow-requests',
      queryParameters: {'page': page, 'per_page': perPage},
    );
    if (response is! Map<String, dynamic>) {
      throw ApiError(message: 'Invalid follow requests response');
    }
    return UsersPageModel.fromJson(response);
  }

  /// Returns the requester, who now follows me.
  Future<PublicUserModel> accept(String userId) async {
    final response = await _api.post(
      'follow-requests/${_id(userId)}/accept',
      {},
    );
    if (response is! Map || response['data'] is! Map) {
      throw ApiError(message: 'Invalid follow request response');
    }
    return PublicUserModel.fromJson(
      Map<String, dynamic>.from(response['data'] as Map),
    );
  }

  Future<void> decline(String userId) async {
    await _api.delete('follow-requests/${_id(userId)}');
  }
}
