import 'package:dio/dio.dart';
import 'package:travibe/core/datasource/remotedata/api_exceptions.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/core/media/media_upload_service.dart';
import 'package:travibe/features/create_post/data/post_image.dart';

/// A "Report a Problem" category: [slug] is sent, [label] is shown.
class ProblemCategory {
  const ProblemCategory(this.slug, this.label);
  final String slug;
  final String label;
}

/// App feedback ("Report a Problem"). The endpoint is a client proposal —
/// see docs/BACKEND_REQUESTS.md ("Support: Report a Problem endpoint");
/// `POST /reports` only moderates posts, comments, users and stories.
class SupportRepo {
  SupportRepo({ApiService? apiService, MediaUploadService? uploads})
    : _api = apiService ?? ApiService(),
      _injectedUploads = uploads;

  final ApiService _api;
  final MediaUploadService? _injectedUploads;
  late final MediaUploadService uploads =
      _injectedUploads ?? MediaUploadService(api: _api);

  /// Same limit as `POST /reports` `description` (maxLength 1000).
  static const maxDescription = 1000;
  static const maxScreenshots = 3;

  /// Proposed until the backend publishes its enum.
  static const categories = [
    ProblemCategory('bug', "Something isn't working"),
    ProblemCategory('account', 'Account & login'),
    ProblemCategory('posts_stories', 'Posts & stories'),
    ProblemCategory('chats', 'Chats & messages'),
    ProblemCategory('notifications', 'Notifications'),
    ProblemCategory('other', 'Other'),
  ];

  /// Presign → upload → finalize (JPEG/PNG/GIF/WebP, ≤ 20 MB). Returns the id.
  Future<int> uploadScreenshot(
    PostImage image, {
    required bool Function() isActive,
    required CancelToken cancelToken,
  }) => uploads.upload(
    filename: image.filename,
    contentType: image.contentType,
    bytes: image.bytes,
    isActive: isActive,
    cancelToken: cancelToken,
    onStage: (_) {},
  );

  /// Proposed `POST /support/problems`.
  Future<void> reportProblem({
    required String category,
    required String description,
    List<int> mediaIds = const [],
  }) async {
    try {
      await _api.post('support/problems', {
        'category': category,
        'description': description,
        if (mediaIds.isNotEmpty) 'media_ids': mediaIds,
      });
    } on DioException catch (e) {
      throw ApiExceptions.handleError(e);
    }
  }
}
