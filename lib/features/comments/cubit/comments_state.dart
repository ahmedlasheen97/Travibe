part of 'comments_cubit.dart';

enum CommentsStatus { initial, loading, loaded, failure }

class CommentThreadState {
  CommentThreadState({
    this.status = CommentsStatus.initial,
    List<CommentModel> comments = const [],
    this.nextCursor,
    this.prevCursor,
    this.hasMore = false,
    this.refreshing = false,
    this.loadingMore = false,
    this.error,
    this.paginationError,
  }) : comments = List.unmodifiable(comments);
  final CommentsStatus status;
  final List<CommentModel> comments;
  final String? nextCursor, prevCursor;
  final bool hasMore;
  final bool refreshing;
  final bool loadingMore;
  final ApiError? error;
  final ApiError? paginationError;

  CommentThreadState copyWith({List<CommentModel>? comments}) =>
      CommentThreadState(
        status: status,
        comments: comments ?? this.comments,
        nextCursor: nextCursor,
        prevCursor: prevCursor,
        hasMore: hasMore,
        refreshing: refreshing,
        loadingMore: loadingMore,
        error: error,
        paginationError: paginationError,
      );
}

class CommentsState {
  CommentsState({
    required this.count,
    Map<int?, CommentThreadState> threads = const {},
    Map<int, CommentModel> known = const {},
    Map<int, CommentModel> deleted = const {},
    this.busy = false,
    this.syncing = false,
    this.syncError,
  }) : threads = Map.unmodifiable(threads),
       known = Map.unmodifiable(known),
       deleted = Map.unmodifiable(deleted);
  final Map<int?, CommentThreadState> threads;
  final Map<int, CommentModel> known;
  final Map<int, CommentModel> deleted;
  final int count;
  final bool busy;
  final bool syncing;
  final ApiError? syncError;
  CommentThreadState thread(int? parentId) =>
      threads[parentId] ?? CommentThreadState();
}

class CommentMutationResult {
  const CommentMutationResult({
    this.confirmed = false,
    this.error,
    this.comment,
  });
  final bool confirmed;
  final ApiError? error;
  final CommentModel? comment;
}
