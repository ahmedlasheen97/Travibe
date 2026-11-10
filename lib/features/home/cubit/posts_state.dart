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
