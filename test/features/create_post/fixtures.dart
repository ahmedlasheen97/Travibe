import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/media/media_upload_service.dart';
import 'package:travibe/features/create_post/data/create_post_repo.dart';
import 'package:travibe/features/create_post/data/create_post_request.dart';
import 'package:travibe/features/create_post/data/post_image.dart';
import 'package:travibe/features/create_post/data/post_image_picker.dart';
import 'package:travibe/features/home/data/post_model.dart';

Map<String, dynamic> postJson({
  String content = 'A trip',
  String visibility = 'public',
}) => {
  'id': 42,
  'type': 'text',
  'user_id': 7,
  'user': {'id': 7, 'name': 'Sara', 'username': 'sara'},
  'content': content,
  'visibility': visibility,
  'media': [],
};

/// A valid 1x1 transparent PNG.
final pngBytes = Uint8List.fromList([
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, //
  0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, //
  120, 156, 99, 0, 1, 0, 0, 5, 0, 1, 13, 10, 45, 180, 0, 0, 0, 0, 73, 69, //
  78, 68, 174, 66, 96, 130,
]);

PostImage postImage(String id, {int? mediaId}) => PostImage(
  localId: id,
  bytes: pngBytes,
  filename: 'post-$id.png',
  contentType: 'image/png',
  mediaId: mediaId,
);

class MemoryCreatePostRepo extends CreatePostRepo {
  final requests = <CreatePostRequest>[];
  ApiError? error;
  Completer<PostModel>? gate;
  Completer<void>? authorGate;
  int authorCalls = 0;
  bool authorError = false;

  @override
  Future<PostAuthorModel> getCurrentAuthor() async {
    authorCalls++;
    await authorGate?.future;
    if (authorError) throw ApiError(message: 'offline');
    return PostAuthorModel.fromJson({
      'id': 7,
      'name': 'Sara',
      'username': 'sara',
    });
  }

  @override
  Future<PostModel> create(CreatePostRequest request) async {
    requests.add(request);
    request.toJson(); // Same validation as the real repo.
    if (gate != null) return gate!.future;
    if (error != null) throw error!;
    return PostModel.fromJson(
      postJson(
        content: request.content.trim(),
        visibility: request.visibility.name,
      ),
    );
  }
}

/// Records uploads; ids start at 100. Fails while [failNext] is positive.
class FakeUploads {
  final uploaded = <String>[];
  final services = <FakeMediaUpload>[];
  int failNext = 0;
  Completer<void>? gate;
  var _next = 100;

  FakeMediaUpload create() {
    final service = FakeMediaUpload(this);
    services.add(service);
    return service;
  }
}

class FakeMediaUpload implements MediaUploadService {
  FakeMediaUpload(this._owner);
  final FakeUploads _owner;
  bool closed = false;

  @override
  Future<int> upload({
    required String filename,
    required String contentType,
    required Uint8List bytes,
    required bool Function() isActive,
    required CancelToken cancelToken,
    required void Function(MediaUploadStage) onStage,
    void Function(int sent, int total)? onProgress,
  }) async {
    onStage(MediaUploadStage.uploading);
    onProgress?.call(bytes.length ~/ 2, bytes.length);
    if (_owner.gate != null) await _owner.gate!.future;
    if (cancelToken.isCancelled || !isActive()) {
      throw ApiError(message: 'Photo upload was cancelled.');
    }
    if (_owner.failNext > 0) {
      _owner.failNext--;
      throw ApiError(message: 'Unable to upload your photo.');
    }
    onStage(MediaUploadStage.processing);
    _owner.uploaded.add(filename);
    return _owner._next++;
  }

  @override
  void close() => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePostImagePicker extends PostImagePicker {
  List<PostImage> gallery = [];
  List<PostImage> camera = [];
  int rejected = 0;
  Object? error;
  final galleryLimits = <int>[];
  int captures = 0;

  @override
  Future<PostImagePick> pickGallery({required int limit}) async {
    galleryLimits.add(limit);
    if (error != null) throw error!;
    return PostImagePick(gallery.take(limit).toList(), rejected: rejected);
  }

  @override
  Future<PostImagePick> capture() async {
    captures++;
    if (error != null) throw error!;
    return PostImagePick(camera);
  }
}
