part of 'posts_cubit.dart';

@immutable
sealed class PostsState {}

final class PostsInitial extends PostsState {}

final class PostsLoading extends PostsState {}

final class PostsLoaded extends PostsState {
  final List<PostModel> posts;
  final bool hasMore;
  final bool isLoadingMore;
  final bool isRefreshing;
  final ApiError? paginationError;
  final ApiError? refreshError;

  PostsLoaded({
    required List<PostModel> posts,
    required this.hasMore,
    this.isLoadingMore = false,
    this.isRefreshing = false,
    this.paginationError,
    this.refreshError,
  }) : posts = List.unmodifiable(posts);
}

final class PostsFailure extends PostsState {
  final ApiError error;
  String get errorMessage => error.message;

  PostsFailure(this.error);
}

extension PostsStateShape on PostsState {
  /// Same list shape as [other]: the same post ids in order and the same
  /// loading/error flags. A feed list rebuilds only when this is false;
  /// changes inside one post (a like, a comment count) are picked up by that
  /// post's card alone.
  bool sameShapeAs(PostsState other) {
    final a = this;
    if (a is! PostsLoaded || other is! PostsLoaded) {
      return identical(a, other);
    }
    if (a.hasMore != other.hasMore ||
        a.isLoadingMore != other.isLoadingMore ||
        a.isRefreshing != other.isRefreshing ||
        a.paginationError != other.paginationError ||
        a.refreshError != other.refreshError ||
        a.posts.length != other.posts.length) {
      return false;
    }
    for (var i = 0; i < a.posts.length; i++) {
      if (a.posts[i].id != other.posts[i].id) return false;
    }
    return true;
  }

  /// The post with [id], or null when it isn't loaded.
  PostModel? postById(String id) {
    final state = this;
    if (state is! PostsLoaded) return null;
    for (final post in state.posts) {
      if (post.id == id) return post;
    }
    return null;
  }
}
