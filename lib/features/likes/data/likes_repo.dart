import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/likes/data/like_model.dart';
import 'package:travibe/core/models/cursor_pagination.dart';
import 'package:travibe/core/models/public_user_model.dart';

class LikesRepo {
  LikesRepo({ApiService? apiService}) : _api = apiService ?? ApiService();
  final ApiService _api;

  void _validate(LikeTarget target) {
    if (target.postId < 1 ||
        (target.commentId != null && target.commentId! < 1)) {
      throw ApiError(message: 'This content is unavailable.');
    }
  }

  Future<LikeValue?> setLiked(LikeTarget target, bool liked) async {
    _validate(target);
    final response = liked
        ? await _api.post('${target.path}/like', {})
        : await _api.delete('${target.path}/like');
    // A successful mutation without state needs a resource read, not a guessed
    // full PostResource or an inference from the number of likes.
    if (response == null ||
        response == '' ||
        (response is Map &&
            !response.containsKey('is_liked') &&
            !response.containsKey('likes_count'))) {
      return null;
    }
    return LikeValue.fromJson(response);
  }

  Future<LikeValue> getState(LikeTarget target) async {
    _validate(target);
    final response = await _api.get(target.path);
    return LikeValue.fromJson(response is Map ? response['data'] : null);
  }

  Future<CursorPage<PublicUserModel>> list(
    LikeTarget target, {
    String? cursor,
    int perPage = 15,
  }) {
    _validate(target);
    return _list('${target.path}/likes', cursor: cursor, perPage: perPage);
  }

  Future<CursorPage<PublicUserModel>> listStory(
    int storyId, {
    String? cursor,
    int perPage = 15,
  }) {
    if (storyId < 1) throw ArgumentError.value(storyId, 'storyId');
    return _list('stories/$storyId/likes', cursor: cursor, perPage: perPage);
  }

  Future<CursorPage<PublicUserModel>> _list(
    String path, {
    String? cursor,
    required int perPage,
  }) async {
    final response = await _api.get(
      path,
      queryParameters: cursorQuery(cursor: cursor, perPage: perPage),
    );
    try {
      return CursorPage<PublicUserModel>.fromJson(
        response,
        (item) => PublicUserModel.fromJson(Map<String, dynamic>.from(item)),
      );
    } on ApiError {
      rethrow;
    } catch (_) {
      throw ApiError(message: 'Unable to read likes. Please try again.');
    }
  }
}
