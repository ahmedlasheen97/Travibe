import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/follow/data/follow_errors.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';

/// What the follow button shows for a user.
enum FollowRelation { follow, following, requested }

class FollowState {
  FollowState({
    Map<String, bool> following = const {},
    Map<String, bool> followsYou = const {},
    Map<String, bool> requested = const {},
    Map<String, PublicUserModel> users = const {},
    Set<String> pending = const {},
    this.revision = 0,
  }) : following = Map.unmodifiable(following),
       followsYou = Map.unmodifiable(followsYou),
       requested = Map.unmodifiable(requested),
       users = Map.unmodifiable(users),
       pending = Set.unmodifiable(pending);
  final Map<String, bool> following;
  final Map<String, bool> followsYou;

  /// Pending outgoing follow requests (private accounts).
  final Map<String, bool> requested;
  final Map<String, PublicUserModel> users;
  final Set<String> pending;

  /// Advances only for confirmed mutations, allowing feed invalidation.
  final int revision;

  FollowRelation relationOf(
    String id, {
    bool initialFollowing = false,
    bool initialRequested = false,
  }) {
    if (following[id] ?? initialFollowing) return FollowRelation.following;
    if (requested[id] ?? initialRequested) return FollowRelation.requested;
    return FollowRelation.follow;
  }
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

  /// Records server-read relationship flags (e.g. a loaded profile) so every
  /// card for this user agrees. Fills only unknown values: confirmed
  /// mutations and status checks are never overridden, and no revision bump.
  void seed(String id, {bool? following, bool? followsYou, bool? requested}) {
    if (isClosed || state.pending.contains(id)) return;
    final addFollowing = following != null && state.following[id] == null;
    final addFollowsYou = followsYou != null && state.followsYou[id] == null;
    final addRequested = requested != null && state.requested[id] == null;
    if (!addFollowing && !addFollowsYou && !addRequested) return;
    _update(
      userId: id,
      following: addFollowing ? following : null,
      followsYou: addFollowsYou ? followsYou : null,
      requested: addRequested ? requested : null,
      pending: {...state.pending},
    );
  }

  /// A follow request from [id] was accepted: they now follow me.
  void markFollowsYou(String id, {PublicUserModel? user}) {
    if (isClosed) return;
    _update(
      userId: id,
      followsYou: true,
      user: user,
      pending: {...state.pending},
      mutated: true,
    );
  }

  void _update({
    String? userId,
    bool? following,
    PublicUserModel? user,
    required Set<String> pending,
    bool mutated = false,
    bool? followsYou,
    bool? requested,
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
        requested: {
          ...state.requested,
          if (userId != null && requested != null) userId: requested,
        },
        users: users,
        pending: pending,
        revision: state.revision + (mutated ? 1 : 0),
      ),
    );
  }

  /// Follows, or — when following or requested — unfollows / cancels the
  /// pending request. Private accounts answer a follow with a request.
  Future<ApiError?> toggle(
    String id, {
    required bool currentlyFollowing,
    bool currentlyRequested = false,
  }) async {
    if (isClosed || state.pending.contains(id)) return null;
    if (!canInteract(id)) {
      return ApiError(
        message: 'Unblock this user before changing follow status.',
      );
    }
    final generation = _generation;
    final relation = state.relationOf(
      id,
      initialFollowing: currentlyFollowing,
      initialRequested: currentlyRequested,
    );
    final next = relation == FollowRelation.follow;
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
        requested: !user.isFollowing && user.followRequested,
        user: user,
        pending: {...state.pending}..remove(id),
        mutated: true,
      );
      return null;
    } catch (e) {
      if (!_current(generation)) return null;
      final error = followError(e, following: next);
      // A conflict indicates that local state may be stale; reconcile without
      // replaying the mutation or treating the conflict as a successful action.
      if (error.statusCode == 409 && _current(generation)) {
        try {
          final result = await repo.status(id);
          if (_current(generation)) {
            _update(
              userId: id,
              following: result.isFollowing,
              requested: !result.isFollowing && result.followRequested,
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
          requested: !result.isFollowing && result.followRequested,
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

  ApiError _error(Object e) => followError(e);
}
