part of 'post_upload_cubit.dart';

sealed class PostUploadState {
  const PostUploadState();
}

class PostUploadIdle extends PostUploadState {
  const PostUploadIdle();
}

class PostUploading extends PostUploadState {
  const PostUploading({required this.progress, this.queued = 0});

  /// 0..1 across every photo plus the final post request.
  final double progress;
  final int queued;
}

class PostUploadFailed extends PostUploadState {
  const PostUploadFailed({
    required this.draft,
    required this.message,
    this.queued = 0,
  });

  /// Kept with any uploaded media ids so a retry skips finished photos.
  final CreatePostRequest draft;
  final String message;
  final int queued;
}

class PostUploadDone extends PostUploadState {
  const PostUploadDone(this.post);
  final PostModel post;
}
