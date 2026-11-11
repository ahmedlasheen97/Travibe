import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/features/create_post/data/create_post_repo.dart';
import 'package:travibe/features/create_post/data/create_post_request.dart';
import 'package:travibe/features/create_post/data/post_image.dart';
import 'package:travibe/features/home/data/post_model.dart';

part 'create_post_state.dart';

/// Local composer state only. Publishing happens in `PostUploadCubit`, which
/// outlives this screen.
class CreatePostCubit extends Cubit<CreatePostState> {
  /// [initialAuthor] is the already-loaded current user; when present the
  /// header shows it at once and [loadAuthor] makes no request.
  CreatePostCubit({CreatePostRepo? repo, PostAuthorModel? initialAuthor})
    : _repo = repo ?? CreatePostRepo(),
      super(CreatePostState(author: initialAuthor));
  final CreatePostRepo _repo;

  static const limitNotice =
      'You can add up to ${CreatePostRequest.maxImages} photos.';
  static const rejectedNotice =
      'Some photos were skipped. Use JPEG, PNG, GIF or WebP under 20 MB.';

  void setContent(String content) {
    if (!isClosed) emit(state.copyWith(content: content));
  }

  void setVisibility(PostVisibility visibility) {
    if (!isClosed) emit(state.copyWith(visibility: visibility));
  }

  void addImages(List<PostImage> picked, {int rejected = 0}) {
    if (isClosed) return;
    final accepted = picked.take(state.remainingImages.clamp(0, picked.length));
    final trimmed = accepted.length < picked.length;
    emit(
      state.copyWith(
        images: [...state.images, ...accepted],
        notice: trimmed
            ? limitNotice
            : rejected > 0
            ? rejectedNotice
            : null,
      ),
    );
  }

  /// Shown when a picker opens with no slots left.
  void notifyLimit() {
    if (!isClosed) emit(state.copyWith(notice: limitNotice));
  }

  void removeImage(String localId) {
    if (isClosed) return;
    emit(
      state.copyWith(
        images: [
          for (final image in state.images)
            if (image.localId != localId) image,
        ],
      ),
    );
  }

  Future<void> loadAuthor() async {
    if (isClosed || state.loadingAuthor || state.author != null) return;
    emit(state.copyWith(loadingAuthor: true, clearAuthorError: true));
    try {
      final author = await _repo.getCurrentAuthor();
      if (!isClosed) emit(state.copyWith(author: author, loadingAuthor: false));
    } catch (_) {
      if (!isClosed) {
        emit(
          state.copyWith(
            loadingAuthor: false,
            authorError: 'Unable to load your profile.',
          ),
        );
      }
    }
  }
}
