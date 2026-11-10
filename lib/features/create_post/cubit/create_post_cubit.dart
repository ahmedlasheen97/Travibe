import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/create_post/data/create_post_repo.dart';
import 'package:travibe/features/create_post/data/create_post_request.dart';
import 'package:travibe/features/home/data/post_model.dart';

part 'create_post_state.dart';

class CreatePostCubit extends Cubit<CreatePostState> {
  CreatePostCubit({CreatePostRepo? repo})
    : _repo = repo ?? CreatePostRepo(),
      super(const CreatePostState());
  final CreatePostRepo _repo;

  void setContent(String content) {
    if (isClosed ||
        state.isSubmitting ||
        state.status == CreatePostStatus.success) {
      return;
    }
    emit(
      state.copyWith(
        content: content,
        status: CreatePostStatus.idle,
        clearError: true,
      ),
    );
  }

  void setVisibility(PostVisibility visibility) {
    if (isClosed ||
        state.isSubmitting ||
        state.status == CreatePostStatus.success) {
      return;
    }
    emit(
      state.copyWith(
        visibility: visibility,
        status: CreatePostStatus.idle,
        clearError: true,
      ),
    );
  }

  Future<void> loadAuthor() async {
    if (isClosed || state.loadingAuthor) return;
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

  Future<void> submit() async {
    if (isClosed ||
        state.isSubmitting ||
        state.status == CreatePostStatus.success) {
      return;
    }
    final request = state.request;
    final validation = request.validationError;
    if (validation != null) {
      emit(
        state.copyWith(
          status: CreatePostStatus.failure,
          error: ApiError(message: validation),
        ),
      );
      return;
    }
    // Set the guard synchronously before the first asynchronous operation.
    emit(state.copyWith(status: CreatePostStatus.submitting, clearError: true));
    try {
      final post = await _repo.create(request);
      if (!isClosed) {
        emit(state.copyWith(status: CreatePostStatus.success, post: post));
      }
    } catch (error) {
      if (!isClosed) {
        emit(
          state.copyWith(
            status: CreatePostStatus.failure,
            error: error is ApiError
                ? error
                : ApiError(
                    message: 'Unable to publish your post. Please try again.',
                  ),
          ),
        );
      }
    }
  }
}
