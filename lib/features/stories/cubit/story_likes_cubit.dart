import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/likes/data/like_model.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';
import 'package:travibe/features/stories/data/story_model.dart';

class StoryLikesState {
  StoryLikesState(Map<int, LikeValue> values, Set<int> refreshRequired)
    : values = Map.unmodifiable(values),
      refreshRequired = Set.unmodifiable(refreshRequired);
  final Map<int, LikeValue> values;
  final Set<int> refreshRequired;
}

/// Shared by Home's viewer routes, separate from Post/Comment endpoint semantics.
/// All counts/flags come from Story Detail. No guessed response or local +1.
class StoryLikesCubit extends Cubit<StoryLikesState> {
  StoryLikesCubit({required this.repo, PreferencesManager? session})
    : session = session ?? PreferencesManager(),
      super(StoryLikesState({}, {})) {
    this.session.addListener(_sessionChanged);
  }
  final StoriesRepo repo;
  final PreferencesManager session;
  final _versions = <int, int>{};
  final _requests = <int, CancelToken>{};
  int _revision = 0;
  int get revision => _revision;

  void accept(StoryDetail detail, {required int requestRevision}) {
    if (isClosed ||
        !session.hasSession ||
        (_versions[detail.id] ?? 0) > requestRevision ||
        state.values[detail.id]?.pending == true) {
      return;
    }
    emit(
      StoryLikesState({
        ...state.values,
        detail.id: LikeValue(isLiked: detail.isLiked, count: detail.likesCount),
      }, {...state.refreshRequired}..remove(detail.id)),
    );
  }

  void _sessionChanged() {
    if (isClosed) return;
    for (final token in _requests.values) {
      token.cancel();
    }
    _requests.clear();
    _versions.clear();
    ++_revision;
    emit(StoryLikesState({}, {}));
  }

  Future<ApiError?> toggle(StoryDetail detail) async {
    if (isClosed ||
        !session.hasSession ||
        detail.isMine ||
        _requests.containsKey(detail.id)) {
      return null;
    }
    if (detail.expiresAt?.isAfter(DateTime.now()) == false) {
      return ApiError(message: 'This Story has expired.', statusCode: 404);
    }
    final id = detail.id;
    final sessionRevision = session.sessionRevision;
    final previous =
        state.values[id] ??
        LikeValue(isLiked: detail.isLiked, count: detail.likesCount);
    final token = CancelToken();
    _requests[id] = token;
    _versions[id] = ++_revision;
    final recovery = state.refreshRequired.contains(id);
    emit(
      StoryLikesState({
        ...state.values,
        id: LikeValue(
          isLiked: previous.isLiked,
          count: previous.count,
          pending: true,
        ),
      }, state.refreshRequired),
    );
    bool active() =>
        !isClosed &&
        session.hasSession &&
        session.sessionRevision == sessionRevision &&
        identical(_requests[id], token);
    var confirmed = false;
    try {
      // A lost write response or failed confirmation requires a read, not another
      // toggle. An explicit subsequent tap can act on the reconciled state.
      if (!recovery) {
        if (previous.isLiked) {
          await repo.unlikeStory(id, cancelToken: token);
        } else {
          await repo.likeStory(id, cancelToken: token);
        }
        confirmed = true;
      }
      if (!active()) return null;
      final fresh = await repo.getStory(id);
      if (!active()) return null;
      if (fresh.id != id ||
          fresh.userId != detail.userId ||
          fresh.expiresAt?.isAfter(DateTime.now()) == false) {
        throw ApiError(message: 'This Story is no longer available.');
      }
      _versions[id] = ++_revision;
      emit(
        StoryLikesState({
          ...state.values,
          id: LikeValue(isLiked: fresh.isLiked, count: fresh.likesCount),
        }, {...state.refreshRequired}..remove(id)),
      );
      return null;
    } catch (error) {
      if (!active()) return null;
      final api = error is ApiError
          ? error
          : ApiError(message: 'Unable to update this Story like.');
      final uncertain =
          recovery ||
          confirmed ||
          api.statusCode == null ||
          api.statusCode! >= 500;
      _versions[id] = ++_revision;
      emit(
        StoryLikesState(
          {...state.values, id: previous},
          {...state.refreshRequired, if (uncertain) id},
        ),
      );
      return uncertain
          ? ApiError(
              message:
                  'Like status could not be confirmed. Tap again to refresh its status before making another change.',
              statusCode: api.statusCode,
            )
          : api;
    } finally {
      if (identical(_requests[id], token)) _requests.remove(id);
    }
  }

  @override
  Future<void> close() {
    session.removeListener(_sessionChanged);
    for (final token in _requests.values) {
      token.cancel();
    }
    _requests.clear();
    return super.close();
  }
}
