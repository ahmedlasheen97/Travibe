import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';

class StoryViewersState {
  const StoryViewersState({
    this.users = const [],
    this.loading = false,
    this.hasMore = false,
    this.error,
  });
  final List<StoryViewerUser> users;
  final bool loading, hasMore;
  final ApiError? error;
}

/// Sheet-scoped pagination; ownership is rechecked before every request.
class StoryViewersCubit extends Cubit<StoryViewersState> {
  StoryViewersCubit({
    required this.storyId,
    required this.repo,
    required this.isOwner,
    this.blocks,
    PreferencesManager? session,
  }) : session = session ?? PreferencesManager(),
       super(const StoryViewersState()) {
    _revision = this.session.sessionRevision;
    this.session.addListener(_sessionChanged);
    _subscription = blocks?.stream.listen((_) {
      if (!isClosed) {
        emit(
          StoryViewersState(
            users: _visible(state.users),
            loading: state.loading,
            hasMore: state.hasMore,
            error: state.error,
          ),
        );
      }
    });
  }
  final int storyId;
  final StoriesRepo repo;
  final bool Function() isOwner;
  final BlockCubit? blocks;
  final PreferencesManager session;
  late final int _revision;
  int _generation = 0, _page = 0;
  bool _refreshing = false;
  StreamSubscription<BlockState>? _subscription;
  bool get _allowed =>
      !isClosed &&
      session.hasSession &&
      session.sessionRevision == _revision &&
      isOwner();
  List<StoryViewerUser> _visible(Iterable<StoryViewerUser> users) =>
      List.unmodifiable(
        users.where(
          (u) =>
              blocks?.state.blockedIds.contains(u.author.id.toString()) != true,
        ),
      );
  void _sessionChanged() {
    if (!isClosed && session.sessionRevision != _revision) {
      ++_generation;
      emit(const StoryViewersState());
    }
  }

  Future<void> refresh() async {
    if (!_allowed || _refreshing) return;
    _refreshing = true;
    _page = 0;
    try {
      // A refresh supersedes an older pagination response, even in flight.
      await _fetch(1, ++_generation);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> loadMore() async {
    if (!_allowed || state.loading || !state.hasMore) return;
    await _fetch(_page + 1, _generation);
  }

  Future<void> _fetch(int page, int generation) async {
    emit(
      StoryViewersState(
        users: page == 1 ? const [] : state.users,
        loading: true,
        hasMore: state.hasMore,
      ),
    );
    try {
      final result = await repo.getViewers(storyId, page: page);
      if (!_allowed || generation != _generation) return;
      final users = <int, StoryViewerUser>{
        if (page > 1)
          for (final u in state.users) u.author.id: u,
        for (final u in result.users) u.author.id: u,
      };
      _page = page;
      emit(
        StoryViewersState(
          users: _visible(users.values),
          hasMore: result.hasMore,
        ),
      );
    } catch (error) {
      if (!_allowed || generation != _generation) return;
      final api = error is ApiError
          ? error
          : ApiError(message: 'Unable to load viewers. Please retry.');
      final revoked = [401, 403, 404].contains(api.statusCode);
      emit(
        StoryViewersState(
          users: revoked ? const [] : state.users,
          hasMore: !revoked && state.hasMore,
          error: api,
        ),
      );
    }
  }

  @override
  Future<void> close() {
    ++_generation;
    session.removeListener(_sessionChanged);
    unawaited(_subscription?.cancel());
    return super.close();
  }
}
