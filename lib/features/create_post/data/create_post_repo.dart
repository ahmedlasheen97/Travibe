import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/create_post/data/create_post_request.dart';
import 'package:travibe/features/home/data/post_model.dart';

class CreatePostRepo {
  CreatePostRepo({ApiService? apiService}) : _api = apiService ?? ApiService();
  final ApiService _api;

  Future<PostModel> create(CreatePostRequest request) async {
    final payload = request.toJson();
    try {
      final response = await _api.post('posts', payload);
      final data = response is Map ? response['data'] : null;
      if (data is! Map || data['id'] is! int || (data['id'] as int) <= 0) {
        throw ApiError(
          message:
              'Unable to read the published post. Please refresh your feed.',
        );
      }
      return PostModel.fromJson(Map<String, dynamic>.from(data));
    } on ApiError {
      rethrow;
    } catch (_) {
      throw ApiError(message: 'Unable to publish your post. Please try again.');
    }
  }

  Future<PostAuthorModel> getCurrentAuthor() async {
    final response = await _api.get('user');
    final data = response is Map ? response['data'] : null;
    if (data is! Map || data['id'] is! int || data['name'] is! String) {
      throw ApiError(message: 'Unable to load your profile.');
    }
    return PostAuthorModel.fromJson(Map<String, dynamic>.from(data));
  }
}
