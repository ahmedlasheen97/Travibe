import 'package:travibe/core/models/cursor_pagination.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/comments/data/comment_model.dart';

class CommentsRepo {
  CommentsRepo({ApiService? apiService}) : _api = apiService ?? ApiService();
  final ApiService _api;

  Future<CommentsPage> list(
    int postId, {
    int? parentId,
    String? cursor,
    int perPage = 15,
  }) async {
    final query = cursorQuery(cursor: cursor, perPage: perPage);
    final response = await _api.get(
      'posts/$postId/comments',
      queryParameters: {
        ...query,
        if (parentId != null) 'parent_id': parentId.toString(),
      },
    );
    final result = CommentsPage.fromJson(response);
    if (result.comments.any(
      (c) => c.postId != postId || c.parentId != parentId,
    )) {
      throw ApiError(message: 'Comments returned for a different thread');
    }
    return result;
  }

  CommentModel _comment(dynamic response, int postId, {int? id}) {
    if (response is! Map || response['data'] is! Map) {
      throw ApiError(message: 'Invalid comment response');
    }
    final result = CommentModel.fromJson(
      Map<String, dynamic>.from(response['data']),
    );
    if (result.postId != postId || (id != null && result.id != id)) {
      throw ApiError(message: 'Comment returned for a different resource');
    }
    return result;
  }

  Future<CommentModel> get(int postId, int id) async =>
      _comment(await _api.get('posts/$postId/comments/$id'), postId, id: id);

  Future<CommentModel> create(int postId, CommentTextRequest request) async {
    final result = _comment(
      await _api.post('posts/$postId/comments', request.toJson()),
      postId,
    );
    if (result.parentId != request.parentId) {
      throw ApiError(message: 'Comment returned for a different thread');
    }
    return result;
  }

  Future<CommentModel> edit(
    int postId,
    int id,
    CommentTextRequest request,
  ) async => _comment(
    await _api.put('posts/$postId/comments/$id', {
      'content': request.toJson()['content'],
    }),
    postId,
    id: id,
  );

  Future<void> delete(int postId, int id) async {
    final response = await _api.delete('posts/$postId/comments/$id');
    if (response is! Map || response['message'] is! String) {
      throw ApiError(message: 'Invalid comment deletion response');
    }
  }

  Future<CommentModel> restore(int postId, int id) async => _comment(
    await _api.post('posts/$postId/comments/$id/restore', {}),
    postId,
    id: id,
  );

  /// Deletion can cascade, so only the backend can supply the resulting count.
  Future<int> commentCount(int postId) async {
    final response = await _api.get('posts/$postId');
    final data = response is Map ? response['data'] : null;
    if (data is! Map ||
        data['id'] != postId ||
        data['comments_count'] is! int ||
        (data['comments_count'] as int) < 0) {
      throw ApiError(message: 'The server did not return a comment count');
    }
    return data['comments_count'] as int;
  }
}
