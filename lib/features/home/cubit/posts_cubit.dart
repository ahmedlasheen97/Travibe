import 'package:travibe/core/models/cursor_pagination.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'dart:async';
import 'package:travibe/features/home/cubit/post_activity_cubit.dart';
import 'package:travibe/features/saved/cubit/saves_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/home/data/posts_page_model.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/features/likes/cubit/likes_cubit.dart';
import 'package:travibe/features/likes/data/like_model.dart';

part 'posts_state.dart';

/// Each tab owns one instance, including its cached posts and request lifecycle.
class PostsCubit extends Cubit<PostsState> {
  PostsCubit({
    PostsRepo? postsRepo,
    this.feed = FeedType.explore,
    LikesCubit? likes,
    this.saves,
    this.userId,
    this.activity,
  }) : _postsRepo = postsRepo ?? PostsRepo(),
       _likes = likes ?? LikesCubit(),
       _ownsLikes = likes == null,
       super(PostsInitial()) {
    _session.addListener(_sessionChanged);
    _likesSubscription = _likes.stream.listen((_) => _syncLikes());
    _activitySubscription = activity?.stream.listen((_) => _syncActivity());
    _saveSession = saves?.session;
    _savesSubscription = saves?.stream.listen((value) {
      if (_saveSession != value.session) {
        _saveSession = value.session;
        ++_generation;
        _firstPageRequest = null;
        _isFetchingMore = false;
        _cursor.clear();
        _hiddenPostIds.clear();
        _removedPosts.clear();
        _postOrder.clear();
        _commentCounts.clear();
        _commentVersions.clear();
        _commentsDisabled.clear();
        _deletedPosts.clear();
        _commentRevision = 0;
        emit(PostsInitial());
        if (userId == null && saves!.authenticated) unawaited(loadPosts());
      } else {
        _syncSaves(); // Reapply saved state without changing pagination.
      }
    });
  }

  void _sessionChanged() {
    if (isClosed) return;
    ++_generation;
    _firstPageRequest = null;
    _isFetchingMore = false;
    _cursor.clear();
    _hiddenPostIds.clear();
    _removedPosts.clear();
    _postOrder.clear();
    _commentCounts.clear();
    _commentVersions.clear();
    _commentsDisabled.clear();
    _deletedPosts.clear();
    _commentRevision = 0;
    emit(PostsInitial());
  }

  /// Immutable author scope; null retains the existing feed behavior.
  final int? userId;
  final PostActivityCubit? activity;
  StreamSubscription<PostActivityState>? _activitySubscription;
  void _syncActivity() {
    final current = state;
    if (isClosed || current is! PostsLoaded) return;
    final posts = [
      for (final post in current.posts)
        if (!_isDeleted(post.id)) _withCommentCount(post),
    ];
    if (posts.length == current.posts.length &&
        posts.indexed.every((e) => identical(e.$2, current.posts[e.$1]))) {
      return;
    }
    emit(
      PostsLoaded(
        posts: posts,
        hasMore: current.hasMore,
        isLoadingMore: current.isLoadingMore,
        isRefreshing: current.isRefreshing,
        paginationError: current.paginationError,
        refreshError: current.refreshError,
      ),
    );
  }

  Future<PostsPageModel> _getPage(String? cursor) => userId == null
      ? _postsRepo.getPosts(feed: feed, cursor: cursor)
      : _postsRepo.getUserPosts(userId: userId!, cursor: cursor);

  final SavesCubit? saves;
  int? _saveSession;
  StreamSubscription<SavesState>? _savesSubscription;
  PostModel _withSavedState(PostModel post) => saves?.apply(post) ?? post;
  final LikesCubit _likes;
  final bool _ownsLikes;
  late final StreamSubscription<LikesState> _likesSubscription;
  void _syncSaves() {
    if (isClosed || state is! PostsLoaded) return;
    final current = state as PostsLoaded;
    final posts = current.posts.map(_withSavedState).toList();
    if (posts.indexed.every(
      (entry) => identical(entry.$2, current.posts[entry.$1]),
    )) {
      return;
    }
    emit(
      PostsLoaded(
        posts: posts,
        hasMore: current.hasMore,
        isLoadingMore: current.isLoadingMore,
        isRefreshing: current.isRefreshing,
        paginationError: current.paginationError,
        refreshError: current.refreshError,
      ),
    );
  }

  LikeTarget? _target(PostModel post) {
    final id = int.tryParse(post.id);
    return id != null && id > 0 ? LikeTarget.post(id) : null;
  }

  Future<ApiError?> toggleLike(PostModel post) {
    final target = _target(post);
    if (target == null) {
      return Future.value(ApiError(message: 'This post is unavailable.'));
    }
    return _likes.toggle(
      target,
      initial: post.hasLikeState
          ? LikeValue(isLiked: post.isLiked, count: post.likesCount)
          : null,
    );
  }

  PostModel _withLikeState(PostModel post) {
    final target = _target(post);
    final value = target == null ? null : _likes.value(target);
    if (value == null ||
        (post.hasLikeState &&
            post.isLiked == value.isLiked &&
            post.likesCount == value.count)) {
      return post;
    }
    return post.copyWith(
      isLiked: value.isLiked,
      likesCount: value.count,
      hasLikeState: true,
    );
  }

  void _acceptLikes(List<PostModel> posts, int revision) => _likes.accept({
    for (final post in posts)
      if (_target(post) != null && post.hasLikeState)
        _target(post)!: LikeValue(
          isLiked: post.isLiked,
          count: post.likesCount,
        ),
  }, requestRevision: revision);

  void _syncLikes() {
    if (isClosed || state is! PostsLoaded) return;
    final current = state as PostsLoaded;
    final posts = current.posts.map(_withLikeState).toList();
    if (posts.indexed.every(
      (entry) => identical(entry.$2, current.posts[entry.$1]),
    )) {
      return;
    }
    emit(
      PostsLoaded(
        posts: posts,
        hasMore: current.hasMore,
        isLoadingMore: current.isLoadingMore,
        isRefreshing: current.isRefreshing,
        paginationError: current.paginationError,
        refreshError: current.refreshError,
      ),
    );
  }

  final PostsRepo _postsRepo;
  final FeedType feed;
  final _cursor = CursorProgress();
  final _session = PreferencesManager();
  int _generation = 0;
  int _dataRevision = 0;
  bool _isFetchingMore = false;
  Future<void>? _firstPageRequest;

  final Set<String> _hiddenPostIds = {};
  final Map<String, int> _postOrder = {};
  final Map<String, ({PostModel post, int dataRevision})> _removedPosts = {};

  int _commentRevision = 0;
  final Map<String, int> _commentVersions = {};
  final Map<String, int> _commentCounts = {};

  PostModel _withCommentCount(PostModel post) {
    final count = activity?.state.comments[post.id] ?? _commentCounts[post.id];
    final disabled =
        activity?.state.commentsDisabled[post.id] ?? _commentsDisabled[post.id];
    if (disabled != null && disabled != post.commentsDisabled) {
      post = post.copyWith(commentsDisabled: disabled);
    }
    return count == null || count == post.commentsCount
        ? post
        : post.copyWith(commentsCount: count, hasCommentCount: true);
  }

  // Local fallbacks when no shared PostActivityCubit is attached.
  final Map<String, bool> _commentsDisabled = {};
  final Set<String> _deletedPosts = {};
  bool _isDeleted(String id) =>
      _deletedPosts.contains(id) ||
      activity?.state.deleted.contains(id) == true;

  /// Deletes the viewer's own post, then removes it from every list.
  Future<ApiError?> deletePost(PostModel post) async {
    try {
      await _postsRepo.deletePost(post.id);
    } catch (error) {
      return _errorFrom(error);
    }
    if (isClosed) return null;
    _deletedPosts.add(post.id);
    activity?.postDeleted(post.id);
    _syncActivity();
    return null;
  }

  /// Turns commenting on/off for the viewer's own post.
  Future<ApiError?> setCommentsDisabled(PostModel post, bool disabled) async {
    try {
      await _postsRepo.setCommentsDisabled(post.id, disabled);
    } catch (error) {
      return _errorFrom(error);
    }
    if (isClosed) return null;
    _commentsDisabled[post.id] = disabled;
    activity?.setCommentsDisabled(post.id, disabled);
    _syncActivity();
    return null;
  }

  /// Apply one authoritative post count to every visible/cached feed occurrence.
  void setCommentsCount(String postId, int count) {
    if (isClosed) return;
    if (activity != null) {
      activity!.setCommentsCount(postId, count);
      return;
    }
    _commentVersions[postId] = ++_commentRevision;
    _commentCounts[postId] = count;
    final current = state;
    if (current is PostsLoaded) {
      emit(
        PostsLoaded(
          posts: _visiblePosts(current.posts),
          hasMore: current.hasMore,
          isLoadingMore: current.isLoadingMore,
          isRefreshing: current.isRefreshing,
          paginationError: current.paginationError,
          refreshError: current.refreshError,
        ),
      );
    }
  }

  void _acceptCommentCounts(List<PostModel> posts, int revision) {
    for (final post in posts) {
      if (!post.hasCommentCount) continue;
      if ((_commentVersions[post.id] ?? 0) <= revision) {
        _commentCounts[post.id] = post.commentsCount;
      }
    }
  }

  Set<String> _blockedUserIds = {};

  bool _isBlockedPost(PostModel post) =>
      _blockedUserIds.contains(post.userId) ||
      _blockedUserIds.contains(post.user.id) ||
      (post.originalPost != null && _isBlockedPost(post.originalPost!));

  void setBlockedUsers(Set<String> ids) {
    if (isClosed) return;
    _blockedUserIds = Set.of(ids);
    final current = state;
    if (current is PostsLoaded) {
      emit(
        PostsLoaded(
          posts: _visiblePosts(current.posts),
          hasMore: current.hasMore,
          isLoadingMore: current.isLoadingMore,
          isRefreshing: current.isRefreshing,
          paginationError: current.paginationError,
          refreshError: current.refreshError,
        ),
      );
    }
  }

  /// Revalidate membership after unblock, waiting out pre-mutation requests.
  Future<void> refreshAfterBlockChange() async {
    if (isClosed || state is PostsInitial) return;
    await pendingLoad;
    if (!isClosed) await refresh();
  }

  List<PostModel> _visiblePosts(List<PostModel> posts) {
    final visible = <PostModel>[];
    for (var i = 0; i < posts.length; i++) {
      final post = _withSavedState(_withLikeState(_withCommentCount(posts[i])));
      if (_isBlockedPost(post) || _isDeleted(post.id)) continue;
      _postOrder.putIfAbsent(post.id, () => _postOrder.length);
      if (userId == null && _hiddenPostIds.contains(post.id)) {
        _removedPosts.putIfAbsent(
          post.id,
          () => (post: post, dataRevision: _dataRevision),
        );
      } else {
        visible.add(post);
      }
    }
    return visible;
  }

  /// Called only after a confirmed backend mutation, on both feed instances.
  void setPostHidden(String postId, bool hidden) {
    if (isClosed || userId != null) return;
    final current = state;
    if (hidden) {
      _hiddenPostIds.add(postId);
    } else {
      _hiddenPostIds.remove(postId);
    }
    if (current is! PostsLoaded) {
      if (!hidden && current is PostsLoading) {
        unawaited(_reloadAfterUnhide());
      }
      return;
    }
    final posts = _visiblePosts(current.posts);
    if (!hidden) {
      final removed = _removedPosts.remove(postId);
      if (removed == null && current.isRefreshing) {
        unawaited(_reloadAfterUnhide());
      } else if (removed != null) {
        if (removed.dataRevision != _dataRevision || current.isRefreshing) {
          // A refreshed feed may have changed membership/ordering. Fetch only
          // this affected feed instead of inserting an obsolete snapshot.
          unawaited(_reloadAfterUnhide());
        } else if (!_isBlockedPost(removed.post) &&
            !posts.any((post) => post.id == postId)) {
          final rank = _postOrder[postId] ?? _postOrder.length;
          final index = posts.indexWhere(
            (post) => (_postOrder[post.id] ?? _postOrder.length) > rank,
          );
          posts.insert(
            index < 0 ? posts.length : index,
            _withLikeState(_withCommentCount(removed.post)),
          );
        }
      }
    }
    emit(
      PostsLoaded(
        posts: posts,
        hasMore: current.hasMore,
        isLoadingMore: current.isLoadingMore,
        isRefreshing: current.isRefreshing,
        paginationError: current.paginationError,
        refreshError: current.refreshError,
      ),
    );
  }

  Future<void> _reloadAfterUnhide() async {
    await pendingLoad;
    if (!isClosed) await refresh();
  }

  /// Lets social mutations wait out an older first-page request before refresh.
  Future<void> get pendingLoad => _firstPageRequest ?? Future.value();

  Future<void> loadPosts() {
    if (isClosed) return Future.value();
    if (_firstPageRequest != null) return _firstPageRequest!;
    final request = _loadFirstPage();
    _firstPageRequest = request;
    return request.whenComplete(() {
      if (identical(_firstPageRequest, request)) _firstPageRequest = null;
    });
  }

  /// A refresh supersedes in-flight pagination; repeated refreshes are coalesced.
  Future<void> refresh() => loadPosts();

  /// Revalidate after creation, even if an older load began before publication.
  Future<void> refreshAfterPublication() async {
    if (isClosed) return;
    await pendingLoad;
    if (!isClosed) await refresh();
  }

  Future<void> _loadFirstPage() async {
    final generation = ++_generation;
    _isFetchingMore = false;
    final previous = state;
    if (previous is PostsLoaded) {
      emit(
        PostsLoaded(
          posts: _visiblePosts(previous.posts),
          hasMore: previous.hasMore,
          isRefreshing: true,
        ),
      );
    } else {
      emit(PostsLoading());
    }
    final commentRevision = activity?.revision ?? _commentRevision;
    final activitySession = activity?.state.session ?? 0;
    final likeRevision = _likes.revision;
    final saveRevision = saves?.revision ?? 0;
    final saveSession = saves?.session ?? 0;
    try {
      final page = await _getPage(null);
      if (isClosed ||
          generation != _generation ||
          (saves != null && saveSession != saves!.session)) {
        return;
      }
      _cursor.accept(page.pagination!);
      _dataRevision++;
      activity?.accept(
        page.posts,
        requestRevision: commentRevision,
        requestSession: activitySession,
      );
      _acceptCommentCounts(page.posts, commentRevision);
      _acceptLikes(page.posts, likeRevision);
      saves?.accept(
        page.posts,
        requestRevision: saveRevision,
        requestSession: saveSession,
      );
      _postOrder.clear();
      emit(
        PostsLoaded(
          posts: _visiblePosts(
            {for (final post in page.posts) post.id: post}.values.toList(),
          ),
          hasMore: _cursor.hasMore,
        ),
      );
    } catch (e) {
      if (isClosed ||
          generation != _generation ||
          (saves != null && saveSession != saves!.session)) {
        return;
      }
      final error = _errorFrom(e);
      if (previous is PostsLoaded &&
          !(userId != null && [401, 403, 404].contains(error.statusCode))) {
        emit(
          PostsLoaded(
            posts: _visiblePosts(
              state is PostsLoaded
                  ? (state as PostsLoaded).posts
                  : previous.posts,
            ),
            hasMore: previous.hasMore,
            paginationError: previous.paginationError,
            refreshError: error,
          ),
        );
      } else {
        emit(PostsFailure(error));
      }
    }
  }

  Future<void> loadMore({bool retry = false}) async {
    final previous = state;
    if (isClosed ||
        _isFetchingMore ||
        _firstPageRequest != null ||
        previous is! PostsLoaded ||
        !previous.hasMore ||
        (previous.paginationError != null && !retry)) {
      return;
    }

    final generation = _generation;
    final requestedCursor = _cursor.nextCursor;
    _isFetchingMore = true;
    emit(
      PostsLoaded(
        posts: _visiblePosts(previous.posts),
        hasMore: previous.hasMore,
        isLoadingMore: true,
        refreshError: previous.refreshError,
      ),
    );
    final commentRevision = activity?.revision ?? _commentRevision;
    final activitySession = activity?.state.session ?? 0;
    final likeRevision = _likes.revision;
    final saveRevision = saves?.revision ?? 0;
    final saveSession = saves?.session ?? 0;
    try {
      final page = await _getPage(requestedCursor);
      if (isClosed ||
          generation != _generation ||
          (saves != null && saveSession != saves!.session)) {
        return;
      }
      _cursor.accept(page.pagination!, requestedCursor: requestedCursor);
      activity?.accept(
        page.posts,
        requestRevision: commentRevision,
        requestSession: activitySession,
      );
      _acceptCommentCounts(page.posts, commentRevision);
      _acceptLikes(page.posts, likeRevision);
      saves?.accept(
        page.posts,
        requestRevision: saveRevision,
        requestSession: saveSession,
      );
      final current = state as PostsLoaded;
      final posts = {for (final post in current.posts) post.id: post};
      for (final post in page.posts) {
        posts[post.id] = post;
      }
      emit(
        PostsLoaded(
          posts: _visiblePosts(posts.values.toList()),
          hasMore: _cursor.hasMore,
          refreshError: previous.refreshError,
        ),
      );
    } catch (e) {
      if (isClosed ||
          generation != _generation ||
          (saves != null && saveSession != saves!.session)) {
        return;
      }
      final error = _errorFrom(e);
      if (userId != null && [401, 403, 404].contains(error.statusCode)) {
        emit(PostsFailure(error));
        return;
      }
      emit(
        PostsLoaded(
          posts: _visiblePosts((state as PostsLoaded).posts),
          hasMore: previous.hasMore,
          paginationError: _errorFrom(e),
          refreshError: previous.refreshError,
        ),
      );
    } finally {
      if (generation == _generation) _isFetchingMore = false;
    }
  }

  ApiError _errorFrom(Object error) => error is ApiError
      ? error
      : ApiError(message: 'Unable to load posts. Please try again.');

  @override
  Future<void> close() async {
    ++_generation;
    _session.removeListener(_sessionChanged);
    await _likesSubscription.cancel();
    await _savesSubscription?.cancel();
    await _activitySubscription?.cancel();
    if (_ownsLikes) await _likes.close();
    return super.close();
  }
}
