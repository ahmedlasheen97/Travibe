part of 'create_post_cubit.dart';

class CreatePostState {
  const CreatePostState({
    this.content = '',
    this.visibility = PostVisibility.public,
    this.images = const [],
    this.notice,
    this.noticeId = 0,
    this.author,
    this.loadingAuthor = false,
    this.authorError,
  });
  final String content;
  final PostVisibility visibility;
  final List<PostImage> images;

  /// One-shot message (limit exceeded, unsupported photo). [noticeId] changes
  /// on every notice so repeating the same message is still shown.
  final String? notice;
  final int noticeId;
  final PostAuthorModel? author;
  final bool loadingAuthor;
  final String? authorError;

  CreatePostRequest get request => CreatePostRequest(
    content: content,
    visibility: visibility,
    images: images,
  );
  bool get canSubmit => request.validationError == null;
  bool get hasUnsavedContent => content.isNotEmpty || images.isNotEmpty;
  int get remainingImages => CreatePostRequest.maxImages - images.length;

  CreatePostState copyWith({
    String? content,
    PostVisibility? visibility,
    List<PostImage>? images,
    String? notice,
    PostAuthorModel? author,
    bool? loadingAuthor,
    String? authorError,
    bool clearAuthorError = false,
  }) => CreatePostState(
    content: content ?? this.content,
    visibility: visibility ?? this.visibility,
    images: images ?? this.images,
    notice: notice ?? this.notice,
    noticeId: notice != null ? noticeId + 1 : noticeId,
    author: author ?? this.author,
    loadingAuthor: loadingAuthor ?? this.loadingAuthor,
    authorError: clearAuthorError ? null : authorError ?? this.authorError,
  );
}
