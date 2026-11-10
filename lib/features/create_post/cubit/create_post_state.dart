part of 'create_post_cubit.dart';

enum CreatePostStatus { idle, submitting, success, failure }

class CreatePostState {
  const CreatePostState({
    this.status = CreatePostStatus.idle,
    this.content = '',
    this.visibility = PostVisibility.public,
    this.error,
    this.post,
    this.author,
    this.loadingAuthor = false,
    this.authorError,
  });
  final CreatePostStatus status;
  final String content;
  final PostVisibility visibility;
  final ApiError? error;
  final PostModel? post;
  final PostAuthorModel? author;
  final bool loadingAuthor;
  final String? authorError;

  bool get isSubmitting => status == CreatePostStatus.submitting;
  CreatePostRequest get request =>
      CreatePostRequest(content: content, visibility: visibility);
  bool get canSubmit =>
      !isSubmitting &&
      status != CreatePostStatus.success &&
      request.validationError == null;

  CreatePostState copyWith({
    CreatePostStatus? status,
    String? content,
    PostVisibility? visibility,
    ApiError? error,
    bool clearError = false,
    PostModel? post,
    PostAuthorModel? author,
    bool? loadingAuthor,
    String? authorError,
    bool clearAuthorError = false,
  }) => CreatePostState(
    status: status ?? this.status,
    content: content ?? this.content,
    visibility: visibility ?? this.visibility,
    error: clearError ? null : error ?? this.error,
    post: post ?? this.post,
    author: author ?? this.author,
    loadingAuthor: loadingAuthor ?? this.loadingAuthor,
    authorError: clearAuthorError ? null : authorError ?? this.authorError,
  );
}
