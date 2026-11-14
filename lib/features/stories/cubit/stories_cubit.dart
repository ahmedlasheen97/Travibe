import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';

class StoriesState {
  StoriesState({
    List<StoryGroup> groups = const [],
    this.loading = false,
    this.loadingMore = false,
    this.hasMore = false,
    this.error,
  }) : groups = List.unmodifiable(groups);
  final List<StoryGroup> groups;
  final bool loading, loadingMore, hasMore;
  final ApiError? error;
}

/// Independent pagination by author group; never shares Home post cursors.
class StoriesCubit extends Cubit<StoriesState> {
  StoriesCubit({
    StoriesRepo? repo,
    PreferencesManager? session,
    this.blocks,
    DateTime Function()? now,
  }) : repo = repo ?? StoriesRepo(),
       session = session ?? PreferencesManager(),
       _now = now ?? DateTime.now,
       super(StoriesState()) {
    this.session.addListener(_sessionChanged);
    _blocked = blocks?.state.blockedIds ?? {};
    _blockSubscription = blocks?.stream.listen((state) {
      if (isClosed) return;
      if (setEquals(_blocked, state.blockedIds)) return;
      _blocked = state.blockedIds;
      ++_generation;
      _page = 0;
      emit(
        StoriesState(
          groups: List.unmodifiable(
            this.state.groups.where(
              (group) => !_blocked.contains(group.user.id.toString()),
            ),
          ),
        ),
      );
      unawaited(refresh());
    });
  }
  final StoriesRepo repo;
  final PreferencesManager session;
  final DateTime Function() _now;
  Timer? _expiry;

  /// The loaded group for [userId], if they have an active Story I can see.
  StoryGroup? groupOf(int? userId) => userId == null
      ? null
      : state.groups.where((g) => g.user.id == userId).firstOrNull;

  @override
  void onChange(Change<StoriesState> change) {
    super.onChange(change);
    _scheduleExpiry(change.nextState);
  }

  /// Drops each Story when it expires, so every ring (Home, Profile) updates
  /// without a refetch.
  void _scheduleExpiry(StoriesState state) {
    _expiry?.cancel();
    _expiry = null;
    DateTime? next;
    for (final group in state.groups) {
      for (final story in group.stories) {
        final at = story.expiresAt;
        if (at != null && (next == null || at.isBefore(next))) next = at;
      }
    }
    if (next == null || isClosed) return;
    final delay = next.difference(_now());
    _expiry = Timer(
      delay.isNegative
          ? Duration.zero
          : delay + const Duration(milliseconds: 1),
      _dropExpired,
    );
  }

  void _dropExpired() {
    if (isClosed) return;
    final now = _now();
    final groups = state.groups
        .map((g) => g.withoutExpired(now))
        .where((g) => g.stories.isNotEmpty)
        .toList();
    final changed =
        groups.length != state.groups.length ||
        !groups.indexed.every((e) => identical(e.$2, state.groups[e.$1]));
    if (!changed) {
      _scheduleExpiry(state);
      return;
    }
    emit(
      StoriesState(
        groups: groups,
        loading: state.loading,
        loadingMore: state.loadingMore,
        hasMore: state.hasMore,
        error: state.error,
      ),
    );
  }

  final BlockCubit? blocks;
  StreamSubscription<BlockState>? _blockSubscription;
  Set<String> _blocked = {};
  final _seen = <int, int>{};
  final _seenVersions = <int, int>{};
  int _viewRevision = 0;
  final _deleted = <int>{};
  void confirmedView(int id, int count) {
    if (isClosed || !session.hasSession) return;
    _seen[id] = count;
    _seenVersions[id] = ++_viewRevision;
    _reconcile();
  }

  void confirmedDelete(int id) {
    if (isClosed || !session.hasSession) return;
    _deleted.add(id);
    _reconcile();
    unawaited(refresh());
  }

  void _reconcile() => emit(
    StoriesState(
      groups: state.groups
          .map((g) => g.reconcile(_seen, _deleted))
          .where((g) => g.stories.isNotEmpty)
          .toList(),
      loading: state.loading,
      loadingMore: state.loadingMore,
      hasMore: state.hasMore,
      error: state.error,
    ),
  );
  int _generation = 0, _page = 0;
  Future<void>? _first;
  void _sessionChanged() {
    _seen.clear();
    _seenVersions.clear();
    _viewRevision = 0;
    _deleted.clear();
    ++_generation;
    _page = 0;
    _first = null;
    emit(StoriesState());
    if (session.hasSession) unawaited(refresh());
  }

  Future<void> load() => _first ?? refresh();
  Future<void> refresh() {
    if (isClosed) return Future.value();
    final generation = ++_generation;
    _page = 0;
    if (!session.hasSession) {
      emit(StoriesState());
      return Future.value();
    }
    emit(StoriesState(groups: state.groups, loading: true));
    return _first = _fetch(1, generation, session.sessionRevision).whenComplete(
      () {
        if (_generation == generation) _first = null;
      },
    );
  }

  Future<void> loadMore() async {
    if (isClosed ||
        state.loading ||
        state.loadingMore ||
        !state.hasMore ||
        !session.hasSession) {
      return;
    }
    emit(StoriesState(groups: state.groups, hasMore: true, loadingMore: true));
    await _fetch(_page + 1, _generation, session.sessionRevision);
  }

  Future<void> _fetch(int page, int generation, int revision) async {
    final readViewRevision = _viewRevision;
    bool current() =>
        !isClosed &&
        generation == _generation &&
        revision == session.sessionRevision &&
        session.hasSession;
    try {
      final result = await repo.getStories(page: page);
      if (!current()) return;
      // A fresh GET owns the count; a read started before a confirmed view must
      // not overwrite its newer result. Seen flags remain safe session-local state.
      for (final group in result.groups) {
        for (final story in group.stories) {
          final version = _seenVersions[story.id];
          if (version != null && version <= readViewRevision) {
            _seen[story.id] = story.viewsCount;
          }
        }
      }
      final groups = <int, StoryGroup>{};
      if (page > 1) {
        for (final group in state.groups) {
          groups[group.user.id] = group;
        }
      }
      for (final group in result.groups) {
        if (_blocked.contains(group.user.id.toString()) ||
            group.stories.isEmpty) {
          continue;
        }
        // Keep backend first-occurrence order, merge overlapping page groups.
        final previous = groups[group.user.id];
        if (previous == null) {
          groups[group.user.id] = group;
        } else {
          groups[group.user.id] = group.merge(previous);
        }
      }
      _page = page;
      emit(
        StoriesState(
          groups: List.unmodifiable(
            groups.values
                .map((g) => g.reconcile(_seen, _deleted))
                .where((g) => g.stories.isNotEmpty),
          ),
          hasMore: result.hasMore,
        ),
      );
    } catch (error) {
      if (!current()) return;
      emit(
        StoriesState(
          groups: state.groups,
          hasMore: state.hasMore,
          error: error is ApiError
              ? error
              : ApiError(message: 'Unable to load Stories. Please retry.'),
        ),
      );
    }
  }

  @override
  Future<void> close() {
    ++_generation;
    _expiry?.cancel();
    session.removeListener(_sessionChanged);
    unawaited(_blockSubscription?.cancel());
    return super.close();
  }
}
