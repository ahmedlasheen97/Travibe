import 'package:dio/dio.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_exceptions.dart';
import 'package:travibe/core/datasource/remotedata/dio_client.dart';
import 'package:travibe/features/stories/data/story_model.dart';

class StoryCreationUncertain extends ApiError {
  StoryCreationUncertain()
    : super(
        message:
            'We couldn’t confirm your story was posted. We’ll check before trying again.',
      );
}

class StoriesRepo {
  StoriesRepo({DioClient? client}) : _dio = (client ?? DioClient()).dio {
    _dio.options.connectTimeout ??= const Duration(seconds: 15);
  }
  final Dio _dio;
  final _pendingViews = <(int, int), Future<void>>{};

  Future<StoriesPage> getStories({int page = 1}) async {
    try {
      final response = await _dio.get(
        'stories',
        queryParameters: {'page': page},
        options: Options(receiveTimeout: const Duration(seconds: 15)),
      );
      if (response.statusCode != 200) throw const FormatException();
      final result = StoriesPage.fromJson(response.data);
      if (result.page != page) throw const FormatException();
      return result;
    } on DioException catch (e) {
      throw ApiExceptions.handleError(e);
    } on FormatException {
      throw ApiError(message: 'Unable to read Stories. Please retry.');
    }
  }

  Future<StoryDetail> getStory(int id) async {
    storyId(id);
    try {
      final response = await _dio.get(
        'stories/$id',
        options: Options(receiveTimeout: const Duration(seconds: 15)),
      );
      if (response.statusCode != 200) throw const FormatException();
      final result = StoryDetail.fromJson(storyObject(response.data)['data']);
      if (result.id != id) throw const FormatException();
      return result;
    } on DioException catch (e) {
      throw ApiExceptions.handleError(e);
    } on FormatException {
      throw ApiError(message: 'Unable to read this Story. Please retry.');
    }
  }

  /// The view response envelope is not verified. Confirm transport success only;
  /// counts and flags are reconciled through the documented detail GET resource.
  Future<void> recordView(int id) {
    storyId(id);
    final key = (PreferencesManager().sessionRevision, id);
    final pending = _pendingViews[key];
    if (pending != null) return pending;
    late final Future<void> request;
    request = _sendView(id).whenComplete(() {
      if (identical(_pendingViews[key], request)) _pendingViews.remove(key);
    });
    _pendingViews[key] = request;
    return request;
  }

  Future<void> _sendView(int id) async {
    try {
      final response = await _dio.post(
        'stories/$id/view',
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      final status = response.statusCode;
      if (status == null || status < 200 || status >= 300) {
        throw ApiError(
          message: 'Unable to confirm this view.',
          statusCode: status,
        );
      }
    } on DioException catch (e) {
      throw ApiExceptions.handleError(e);
    }
  }

  /// Mutation bodies are unverified; accept HTTP success without decoding JSON.
  /// The caller reconciles flags/counts through the documented detail resource.
  Future<void> likeStory(int id, {CancelToken? cancelToken}) =>
      _setStoryLiked(id, true, cancelToken);

  Future<void> unlikeStory(int id, {CancelToken? cancelToken}) =>
      _setStoryLiked(id, false, cancelToken);

  Future<void> _setStoryLiked(int id, bool liked, CancelToken? token) async {
    storyId(id);
    try {
      final response = await _dio.request<dynamic>(
        'stories/$id/like',
        cancelToken: token,
        options: Options(
          method: liked ? 'POST' : 'DELETE',
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      final status = response.statusCode;
      if (status == null || status < 200 || status >= 300) {
        throw ApiError(
          message: 'Unable to update this Story like.',
          statusCode: status,
        );
      }
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      throw ApiError(
        statusCode: status,
        message: switch (status) {
          401 => 'Your session has expired. Please sign in again.',
          403 => 'You do not have access to this Story.',
          404 => 'This Story has expired or is no longer available.',
          422 => 'This Story like could not be updated.',
          429 => 'Too many requests. Please wait before trying again.',
          _ =>
            error.response == null
                ? ApiExceptions.handleError(error).message
                : 'Unable to update this Story like. Please retry.',
        },
      );
    }
  }

  Future<void> deleteStory(int id) async {
    storyId(id);
    try {
      final response = await _dio.delete(
        'stories/$id',
        options: Options(receiveTimeout: const Duration(seconds: 15)),
      );
      if (response.statusCode != 200 ||
          storyObject(response.data)['message'] is! String) {
        throw const FormatException();
      }
    } on DioException catch (e) {
      throw ApiExceptions.handleError(e);
    } on FormatException {
      throw ApiError(
        message:
            'Deletion could not be confirmed. Refresh Stories before retrying.',
      );
    }
  }

  Future<StoryViewersPage> getViewers(
    int id, {
    int page = 1,
    int perPage = 15,
  }) async {
    storyId(id);
    try {
      final response = await _dio.get(
        'stories/$id/viewers',
        queryParameters: {'page': page, 'per_page': perPage},
        options: Options(receiveTimeout: const Duration(seconds: 15)),
      );
      if (response.statusCode != 200) throw const FormatException();
      final result = StoryViewersPage.fromJson(response.data);
      if (result.page != page) throw const FormatException();
      return result;
    } on DioException catch (e) {
      throw ApiExceptions.handleError(e);
    } on FormatException {
      throw ApiError(message: 'Unable to read Story viewers.');
    }
  }

  /// Read-only check after an uncertain `POST /stories`: returns the caller's
  /// Story that claimed [mediaId], or null if no Story was created. Throws if
  /// the answer cannot be determined (then nothing may be re-posted yet).
  ///
  /// `GET /media/{id}` reports `mediable_type`/`mediable_id` once media is
  /// claimed. Its docs name posts and comments only, so the caller's own
  /// active Stories are also checked by photo id.
  Future<StoryDetail?> findStoryByMedia(int mediaId) async {
    storyId(mediaId);
    try {
      final response = await _dio.get(
        'media/$mediaId',
        options: Options(receiveTimeout: const Duration(seconds: 15)),
      );
      if (response.statusCode != 200) throw const FormatException();
      final media = storyObject(storyObject(response.data)['data']);
      final type = media['mediable_type'];
      final owner = media['mediable_id'];
      if (type is String && owner is int && owner > 0) {
        if (!type.toLowerCase().contains('story')) return null;
        final story = await getStory(owner);
        return story.isMine && story.media.id == mediaId ? story : null;
      }
      // Fallback: the caller's group comes first and holds at most 10 Stories.
      final page = await getStories();
      if (page.groups.isEmpty) return null;
      for (final summary in page.groups.first.stories) {
        final story = await getStory(summary.id);
        if (!story.isMine) return null;
        if (story.media.id == mediaId) return story;
      }
      return null;
    } on DioException catch (e) {
      throw ApiExceptions.handleError(e);
    } on FormatException {
      throw ApiError(
        message: 'Unable to confirm whether the Story was posted.',
      );
    }
  }

  Future<StoryDetail> create(
    CreateStoryRequest request, {
    CancelToken? cancelToken,
  }) async {
    final payload = request.toJson();
    try {
      final response = await _dio.post(
        'stories',
        data: payload,
        cancelToken: cancelToken,
        options: Options(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      if (response.statusCode != 201) throw StoryCreationUncertain();
      final result = StoryDetail.fromJson(storyObject(response.data)['data']);
      if (result.media.id != request.mediaId ||
          result.visibility != request.draft.audience.visibility ||
          !result.isMine) {
        throw StoryCreationUncertain();
      }
      return result;
    } on FormatException {
      throw StoryCreationUncertain();
    } on DioException catch (e) {
      // A response timeout, lost connection after dispatch, server error or
      // cancellation may follow creation. No invented idempotency key/retry.
      if (e.response == null || (e.response?.statusCode ?? 0) >= 500) {
        throw StoryCreationUncertain();
      }
      throw ApiExceptions.handleError(e);
    }
  }
}
