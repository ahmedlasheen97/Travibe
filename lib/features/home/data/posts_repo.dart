import 'package:travibe/core/models/cursor_pagination.dart';
import 'package:dio/dio.dart';
import 'package:travibe/features/saved/data/saved_posts_page.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_exceptions.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/home/data/posts_page_model.dart';
import 'package:travibe/features/home/data/hidden_post_response.dart';
import 'package:travibe/features/home/data/post_model.dart';

enum FeedType { explore, following }

class PostsRepo {
  PostsRepo({ApiService? apiService})
    : _apiService = apiService ?? ApiService();

  final ApiService _apiService;

  Future<PostsPageModel> getUserPosts({
    required int userId,
    String? cursor,
    int perPage = 15,
  }) => listPosts(userId: userId, cursor: cursor, perPage: perPage);

  /// GET /posts, with optional author scope; feed timelines have separate routes.
  Future<PostsPageModel> listPosts({
    int? userId,
    String? cursor,
    int perPage = 15,
  }) async {
    if (userId != null && userId < 1) {
      throw ArgumentError('Invalid author pagination');
    }
    final query = cursorQuery(cursor: cursor, perPage: perPage);
    try {
      final response = await _apiService.get(
        'posts',
        queryParameters: {'user_id': ?userId, ...query},
      );
      if (response is! Map<String, dynamic> ||
          response['data'] is! List ||
          response['meta'] is! Map) {
        throw ApiError(
          message: 'Unable to read profile posts. Please try again.',
        );
      }
      for (final raw in response['data'] as List) {
        if (raw is! Map ||
            raw['id'] is! int ||
            (raw['id'] as int) < 1 ||
            (userId != null &&
                (raw['user_id'] is! int || raw['user_id'] != userId))) {
          throw ApiError(
            message:
                'The server returned invalid author posts. Please try again.',
          );
        }
      }
      return PostsPageModel.fromCursorJson(response);
    } on ApiError {
      rethrow;
    } on DioException catch (error) {
      throw ApiExceptions.handleError(error);
    } catch (_) {
      throw ApiError(
        message: 'Unable to load profile posts. Please try again.',
      );
    }
  }

  Future<bool> setSaved(String postId, bool saved) async {
    final id = int.tryParse(postId);
    if (id == null || id < 1) throw ArgumentError.value(postId, 'postId');
    try {
      final response = saved
          ? await _apiService.post('posts/$id/save', {})
          : await _apiService.delete('posts/$id/save');
      if (response is! Map ||
          response['is_saved'] is! bool ||
          response['is_saved'] != saved) {
        throw ApiError(
          message:
              'The server did not confirm the bookmark. Please refresh and try again.',
        );
      }
      return response['is_saved'] as bool;
    } on ApiError {
      rethrow;
    } on DioException catch (e) {
      throw ApiExceptions.handleError(e);
    } catch (_) {
      throw ApiError(
        message: 'Unable to update the bookmark. Please try again.',
      );
    }
  }

  Future<PostsPageModel> getSavedPosts({int page = 1, int perPage = 15}) async {
    if (page < 1 || perPage < 1 || perPage > 100) {
      throw ArgumentError('Invalid saved pagination');
    }
    try {
      final response = await _apiService.get(
        'users/me/saved',
        queryParameters: {'page': page, 'per_page': perPage},
      );
      return parseSavedPostsPage(response, requestedPage: page);
    } on ApiError {
      rethrow;
    } on DioException catch (e) {
      throw ApiExceptions.handleError(e);
    } catch (_) {
      throw ApiError(message: 'Unable to load saved posts. Please try again.');
    }
  }

  /// `DELETE /posts/{post}` (author only; soft delete).
  Future<void> deletePost(String postId) async {
    final id = int.tryParse(postId);
    if (id == null || id < 1) throw ArgumentError.value(postId, 'postId');
    try {
      await _apiService.delete('posts/$id');
    } on ApiError {
      rethrow;
    } on DioException catch (e) {
      throw ApiExceptions.handleError(e);
    } catch (_) {
      throw ApiError(message: 'Unable to delete the post. Please try again.');
    }
  }

  /// `PUT /posts/{post}` with `comments_disabled` (author only).
  Future<PostModel> setCommentsDisabled(String postId, bool disabled) async {
    final id = int.tryParse(postId);
    if (id == null || id < 1) throw ArgumentError.value(postId, 'postId');
    try {
      final response = await _apiService.put('posts/$id', {
        'comments_disabled': disabled,
      });
      final data = response is Map ? response['data'] : null;
      if (data is! Map || data['comments_disabled'] != disabled) {
        throw ApiError(
          message:
              'The server did not confirm the commenting change. Please refresh and try again.',
        );
      }
      return PostModel.fromJson(Map<String, dynamic>.from(data));
    } on ApiError {
      rethrow;
    } on DioException catch (e) {
      throw ApiExceptions.handleError(e);
    } catch (_) {
      throw ApiError(message: 'Unable to update commenting. Please try again.');
    }
  }

  Future<HiddenPostResponse> setHidden(String postId, bool hidden) async {
    final id = int.tryParse(postId);
    if (id == null) throw ArgumentError.value(postId, 'postId');
    final endpoint = 'posts/$id/hide';
    final response = hidden
        ? await _apiService.post(endpoint, {})
        : await _apiService.delete(endpoint);
    final result = HiddenPostResponse.fromJson(response);
    if (result.isHidden != hidden) {
      throw ApiError(
        message: 'The server did not confirm the requested hidden state',
      );
    }
    return result;
  }

  Future<PostsPageModel> getPosts({
    FeedType feed = FeedType.explore,
    String? cursor,
    int perPage = 15,
  }) async {
    final query = cursorQuery(cursor: cursor, perPage: perPage);
    try {
      final response = await _apiService.get(
        'feed/${feed.name}',
        queryParameters: query,
      );
      if (response is! Map<String, dynamic> ||
          response['data'] is! List ||
          response['meta'] is! Map) {
        throw ApiError(message: 'Invalid feed response format');
      }
      return PostsPageModel.fromCursorJson(response);
    } on ApiError {
      rethrow;
    } on DioException catch (e) {
      throw ApiExceptions.handleError(e);
    } catch (_) {
      throw ApiError(message: 'Unable to read the feed response');
    }
  }
}
