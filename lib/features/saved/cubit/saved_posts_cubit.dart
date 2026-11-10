import 'package:travibe/features/home/cubit/post_activity_cubit.dart';
import 'package:travibe/features/likes/cubit/likes_cubit.dart';
import 'package:travibe/features/likes/data/like_model.dart';
import 'package:travibe/features/shares/cubit/shares_cubit.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/features/saved/cubit/saves_cubit.dart';

enum SavedPostsStatus { initial, loading, loaded, failure }

class SavedPostsState {
  SavedPostsState({
    this.status = SavedPostsStatus.initial,
    List<PostModel> posts = const [],
    this.hasMore = false,
    this.refreshing = false,
    this.loadingMore = false,
    this.error,
    this.paginationError,
  }) : posts = List.unmodifiable(posts);
  final SavedPostsStatus status;
  final List<PostModel> posts;
  final bool hasMore;
  final bool refreshing;
  final bool loadingMore;
  final ApiError? error;
  final ApiError? paginationError;
}

/// Separate list/pagination from Explore/Following. Shared bookmark truth only.
class SavedPostsCubit extends Cubit<SavedPostsState> {
  SavedPostsCubit({
    required this.saves,
    PostsRepo? repo,
    this.blocks,
    this.activity,
    this.likes,
    this.shares,
  }) : repo = repo ?? saves.repo,
       super(SavedPostsState()) {
    _session = saves.session;
    _mutation = saves.revision;
    _saveSubscription = saves.stream.listen(_sync);
    _blockSubscription = blocks?.stream.listen((state) {
      if (setEquals(state.blockedIds, _blockedIds)) return;
      _blockedIds = state.blockedIds;
      _publishVisible();
      if (this.state.status != SavedPostsStatus.initial) unawaited(refresh());
    });
    _blockedIds = blocks?.state.blockedIds ?? {};
  }
  final SavesCubit saves;
  final PostsRepo repo;
  final BlockCubit? blocks;
  final PostActivityCubit? activity;
  final LikesCubit? likes;
  final SharesCubit? shares;
  ({int comments, int likes, int shares, int session}) _snapshot() => (
    comments: activity?.revision ?? 0,
    likes: likes?.revision ?? 0,
    shares: shares?.revision ?? 0,
    session: activity?.state.session ?? 0,
  );
  void _acceptInteractions(
    List<PostModel> posts,
    ({int comments, int likes, int shares, int session}) snapshot,
  ) {
    activity?.accept(
      posts,
      requestRevision: snapshot.comments,
      requestSession: snapshot.session,
    );
    likes?.accept({
      for (final p in posts)
        if (p.hasLikeState)
          LikeTarget.post(int.parse(p.id)): LikeValue(
            isLiked: p.isLiked,
            count: p.likesCount,
          ),
    }, requestRevision: snapshot.likes);
    shares?.acceptCounts({
      for (final p in posts)
        if (p.hasShareCount) int.parse(p.id): p.sharesCount,
    }, requestRevision: snapshot.shares);
  }

  late final StreamSubscription<SavesState> _saveSubscription;
  StreamSubscription<BlockState>? _blockSubscription;
  late int _session;
  late int _mutation;
  Set<String> _blockedIds = {};
  int _generation = 0;
  int _page = 0;
  Future<void>? _first;

  bool _blocked(PostModel p) =>
      blocks?.state.blockedIds.contains(p.user.id) == true ||
      blocks?.state.blockedIds.contains(p.userId) == true ||
      (p.originalPost != null && _blocked(p.originalPost!));
  List<PostModel> _visible(Iterable<PostModel> posts) =>
      posts.map(saves.apply).where((p) => p.isSaved && !_blocked(p)).toList();

  void _sync(SavesState value) {
    if (isClosed) return;
    if (_session != value.session) {
      _session = value.session;
      _mutation = value.revision;
      ++_generation;
      _page = 0;
      _first = null;
      emit(SavedPostsState());
      return;
    }
    _publishVisible();
    if (_mutation != value.revision) {
      _mutation = value.revision;
      // Re-fetch server membership/order, also resetting shifted page offsets.
      if (state.status != SavedPostsStatus.initial) unawaited(refresh());
    }
  }

  void _publishVisible() {
    if (isClosed || state.status != SavedPostsStatus.loaded) return;
    emit(
      SavedPostsState(
        status: state.status,
        posts: _visible(state.posts),
        hasMore: state.hasMore,
        refreshing: state.refreshing,
        loadingMore: state.loadingMore,
        error: state.error,
        paginationError: state.paginationError,
      ),
    );
  }

  Future<void> load() => _first ?? _loadFirst();
  Future<void> refresh() => _loadFirst();
  Future<void> _loadFirst() {
    if (isClosed) return Future.value();
    final generation = ++_generation;
    final session = saves.session;
    final revision = saves.revision;
    final previous = state;
    if (!saves.authenticated) {
      emit(
        SavedPostsState(
          status: SavedPostsStatus.failure,
          error: ApiError(
            message: 'Please sign in to view saved posts.',
            statusCode: 401,
          ),
        ),
      );
      return Future.value();
    }
    emit(
      SavedPostsState(
        status: previous.status == SavedPostsStatus.loaded
            ? SavedPostsStatus.loaded
            : SavedPostsStatus.loading,
        posts: _visible(previous.posts),
        hasMore: previous.hasMore,
        refreshing: previous.status == SavedPostsStatus.loaded,
      ),
    );
    final request = _fetchFirst(generation, session, revision);
    _first = request;
    return request.whenComplete(() {
      if (generation == _generation) _first = null;
    });
  }

  bool _current(int generation, int session) =>
      !isClosed && generation == _generation && session == saves.session;
  Future<void> _fetchFirst(int generation, int session, int revision) async {
    try {
      final snapshot = _snapshot();
      final page = await repo.getSavedPosts();
      if (!_current(generation, session)) return;
      _acceptInteractions(page.posts, snapshot);
      saves.accept(
        page.posts,
        requestRevision: revision,
        requestSession: session,
      );
      _page = page.currentPage;
      emit(
        SavedPostsState(
          status: SavedPostsStatus.loaded,
          posts: _visible(page.posts),
          hasMore: page.hasMore,
        ),
      );
    } catch (e) {
      if (!_current(generation, session)) return;
      final error = _error(e);
      final keep =
          state.status == SavedPostsStatus.loaded &&
          ![401, 403].contains(error.statusCode);
      emit(
        SavedPostsState(
          status: keep ? SavedPostsStatus.loaded : SavedPostsStatus.failure,
          posts: keep ? _visible(state.posts) : const [],
          hasMore: keep && state.hasMore,
          error: error,
        ),
      );
    }
  }

  Future<void> loadMore({bool retry = false}) async {
    if (isClosed ||
        _first != null ||
        state.status != SavedPostsStatus.loaded ||
        !state.hasMore ||
        state.loadingMore ||
        (state.paginationError != null && !retry)) {
      return;
    }
    final generation = _generation;
    final session = saves.session;
    final revision = saves.revision;
    emit(
      SavedPostsState(
        status: state.status,
        posts: state.posts,
        hasMore: state.hasMore,
        loadingMore: true,
        error: state.error,
      ),
    );
    try {
      final snapshot = _snapshot();
      final page = await repo.getSavedPosts(page: _page + 1);
      if (!_current(generation, session)) return;
      _acceptInteractions(page.posts, snapshot);
      saves.accept(
        page.posts,
        requestRevision: revision,
        requestSession: session,
      );
      _page = page.currentPage;
      final merged = {
        for (final p in state.posts) p.id: p,
        for (final p in page.posts) p.id: p,
      };
      emit(
        SavedPostsState(
          status: SavedPostsStatus.loaded,
          posts: _visible(merged.values),
          hasMore: page.hasMore,
          error: state.error,
        ),
      );
    } catch (e) {
      if (!_current(generation, session)) return;
      final error = _error(e);
      if ([401, 403].contains(error.statusCode)) {
        emit(SavedPostsState(status: SavedPostsStatus.failure, error: error));
      } else {
        emit(
          SavedPostsState(
            status: SavedPostsStatus.loaded,
            posts: _visible(state.posts),
            hasMore: state.hasMore,
            paginationError: error,
            error: state.error,
          ),
        );
      }
    }
  }

  ApiError _error(Object e) => e is ApiError
      ? e
      : ApiError(message: 'Unable to load saved posts. Please try again.');
  @override
  Future<void> close() async {
    ++_generation;
    await _saveSubscription.cancel();
    await _blockSubscription?.cancel();
    return super.close();
  }
}
