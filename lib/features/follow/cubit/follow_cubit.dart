import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';

class FollowState {
  FollowState({
    Map<String, bool> following = const {},
    Map<String, bool> followsYou = const {},
    Map<String, PublicUserModel> users = const {},
    Set<String> pending = const {},
    this.revision = 0,
  }) : following = Map.unmodifiable(following),
       followsYou = Map.unmodifiable(followsYou),
       users = Map.unmodifiable(users),
       pending = Set.unmodifiable(pending);
  final Map<String, bool> following;
  final Map<String, bool> followsYou;
  final Map<String, PublicUserModel> users;
  final Set<String> pending;

  /// Advances only for confirmed mutations, allowing feed invalidation.
  final int revision;
}

/// Scoped to Root, never a process-wide singleton or a persisted account cache.
class FollowCubit extends Cubit<FollowState> {
  FollowCubit({FollowRepo? repo})
    : repo = repo ?? FollowRepo(),
      super(FollowState()) {
    _preferences.addListener(_sessionChanged);
  }
  final _preferences = PreferencesManager();
  int _generation = 0;
  void _sessionChanged() {
    ++_generation;
    _blocked.clear();
    _blockPending.clear();
    if (!isClosed) emit(FollowState());
  }

  bool _current(int generation) => !isClosed && generation == _generation;
  @override
  Future<void> close() {
    ++_generation;
    _preferences.removeListener(_sessionChanged);
    return super.close();
  }

  final FollowRepo repo;

  final Set<String> _blocked = {};
  final Set<String> _blockPending = {};

  bool canInteract(String id) =>
      !_blocked.contains(id) && !_blockPending.contains(id);

  void setBlockPending(String id, bool pending) {
    if (isClosed) return;
    if (pending) {
      _blockPending.add(id);
    } else {
      _blockPending.remove(id);
    }
    _update(pending: {...state.pending});
  }

  /// Block responses preserve follows; never synthesize an unfollow.
  void applyBlockStatus(String id, bool blocked, {PublicUserModel? user}) {
    if (isClosed) return;
    if (blocked) {
      _blocked.add(id);
    } else {
      _blocked.remove(id);
    }
    _update(
      userId: user?.id,
      following: user?.isFollowing,
      user: user,
      pending: {...state.pending},
    );
  }

  void _update({
    String? userId,
    bool? following,
    PublicUserModel? user,
    required Set<String> pending,
    bool mutated = false,
    bool? followsYou,
  }) {
    final users = {...state.users};
    if (user != null) users[user.id] = user;
    emit(
      FollowState(
        following: {
          ...state.following,
          if (userId != null && following != null) userId: following,
        },
        followsYou: {
          ...state.followsYou,
          if (userId != null && followsYou != null) userId: followsYou,
        },
        users: users,
        pending: pending,
        revision: state.revision + (mutated ? 1 : 0),
      ),
    );
  }

  Future<ApiError?> toggle(
    String id, {
    required bool currentlyFollowing,
  }) async {
    if (isClosed || state.pending.contains(id)) return null;
    if (!canInteract(id)) {
      return ApiError(
        message: 'Unblock this user before changing follow status.',
      );
    }
    final generation = _generation;
    final next = !(state.following[id] ?? currentlyFollowing);
    _update(pending: {...state.pending, id});
    try {
      final user = await repo.setFollowing(id, next);
      if (!_current(generation)) return null;
      if (user.id != id) {
        throw ApiError(message: 'Follow returned a different user');
      }
      _update(
        userId: id,
        following: user.isFollowing,
        user: user,
        pending: {...state.pending}..remove(id),
        mutated: true,
      );
      return null;
    } catch (e) {
      if (!_current(generation)) return null;
      final error = _error(e);
      // A conflict indicates that local state may be stale; reconcile without
      // replaying the mutation or treating the conflict as a successful action.
      if (error.statusCode == 409 && _current(generation)) {
        try {
          final result = await repo.status(id);
          if (_current(generation)) {
            _update(
              userId: id,
              following: result.isFollowing,
              pending: {...state.pending},
            );
          }
        } catch (_) {
          // Keep the original backend conflict available to the caller.
        }
      }
      if (_current(generation)) {
        _update(pending: {...state.pending}..remove(id));
      }
      return error;
    }
  }

  Future<ApiError?> checkStatus(String id) async {
    if (isClosed || state.pending.contains(id) || _blockPending.contains(id)) {
      return null;
    }
    final generation = _generation;
    _update(pending: {...state.pending, id});
    try {
      final result = await repo.status(id);
      if (_current(generation)) {
        _update(
          userId: id,
          following: result.isFollowing,
          pending: {...state.pending}..remove(id),
        );
      }
      return null;
    } catch (e) {
      if (_current(generation)) {
        _update(pending: {...state.pending}..remove(id));
      }
      return _error(e);
    }
  }

  Future<ApiError?> removeFollower(String id) async {
    if (isClosed || state.pending.contains(id)) return null;
    if (!canInteract(id)) return ApiError(message: 'This user is unavailable.');
    final generation = _generation;
    _update(pending: {...state.pending, id});
    try {
      await repo.removeFollower(id);
      if (!_current(generation)) return null;
      _update(
        userId: id,
        followsYou: false,
        user: state.users[id]?.copyWith(followsYou: false),
        pending: {...state.pending}..remove(id),
        mutated: true,
      );
      return null;
    } catch (error) {
      if (!_current(generation)) return null;
      _update(pending: {...state.pending}..remove(id));
      return _error(error);
    }
  }

  ApiError _error(Object e) => e is ApiError
      ? e
      : ApiError(message: 'Unable to update follow status. Please try again.');
}
