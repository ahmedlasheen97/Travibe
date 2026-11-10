part of 'shares_cubit.dart';

class PostShareState {
  const PostShareState({
    this.count,
    this.ownShare,
    this.ownershipKnown = false,
    this.loading = false,
    this.pending = false,
    this.error,
    this.syncError,
  });
  final int? count;
  final ShareModel? ownShare;
  final bool ownershipKnown;
  final bool loading;
  final bool pending;
  final ApiError? error;
  final ApiError? syncError;
  PostShareState copyWith({
    int? count,
    ShareModel? ownShare,
    bool clearOwn = false,
    bool? ownershipKnown,
    bool? loading,
    bool? pending,
    ApiError? error,
    ApiError? syncError,
    bool clearError = false,
    bool clearSyncError = false,
  }) => PostShareState(
    count: count ?? this.count,
    ownShare: clearOwn ? null : ownShare ?? this.ownShare,
    ownershipKnown: ownershipKnown ?? this.ownershipKnown,
    loading: loading ?? this.loading,
    pending: pending ?? this.pending,
    error: clearError ? null : error ?? this.error,
    syncError: clearSyncError ? null : syncError ?? this.syncError,
  );
}

class SharesState {
  SharesState(Map<int, PostShareState> posts) : posts = Map.unmodifiable(posts);
  final Map<int, PostShareState> posts;
  PostShareState post(int id) => posts[id] ?? const PostShareState();
}

class ShareOutcome {
  const ShareOutcome({
    this.confirmed = false,
    this.removed = false,
    this.error,
  });
  final bool confirmed;
  final bool removed;
  final ApiError? error;
}
