import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/block/data/block_repo.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/search/data/users_page_model.dart';

class BlockState {
  BlockState({
    Map<String, bool> blocked = const {},
    Map<String, PublicUserModel> users = const {},
    Set<String> pending = const {},
    this.unblockRevision = 0,
    this.mutationRevision = 0,
  }) : blocked = Map.unmodifiable(blocked),
       users = Map.unmodifiable(users),
       pending = Set.unmodifiable(pending);
  final Map<String, bool> blocked;
  final Map<String, PublicUserModel> users;
  final Set<String> pending;
  final int unblockRevision;
  final int mutationRevision;
  bool isBlocked(String id, {bool fallback = false}) => blocked[id] ?? fallback;
  Set<String> get blockedIds =>
      blocked.entries.where((e) => e.value).map((e) => e.key).toSet();
}

/// Owned by Root; shared across pushed routes and cleared with that session.
class BlockCubit extends Cubit<BlockState> {
  BlockCubit({required this.follow, BlockRepo? repo})
    : repo = repo ?? BlockRepo(),
      super(BlockState());
  final BlockRepo repo;
  final FollowCubit follow;
  int _revision = 0;
  int _listGeneration = 0;
  final Map<String, int> _versions = {};

  void _pending(String id, bool pending) {
    final ids = {...state.pending};
    if (pending) {
      ids.add(id);
    } else {
      ids.remove(id);
    }
    follow.setBlockPending(id, pending);
    emit(
      BlockState(
        blocked: state.blocked,
        users: state.users,
        pending: ids,
        unblockRevision: state.unblockRevision,
        mutationRevision: state.mutationRevision,
      ),
    );
  }

  void _commit(
    String id,
    bool blocked, {
    PublicUserModel? user,
    bool mutated = false,
  }) {
    final wasBlocked = state.isBlocked(id);
    _versions[id] = ++_revision;
    follow.applyBlockStatus(id, blocked, user: user);
    final users = {...state.users};
    if (user != null) users[id] = user;
    emit(
      BlockState(
        blocked: {...state.blocked, id: blocked},
        users: users,
        pending: state.pending,
        unblockRevision:
            state.unblockRevision +
            (!blocked && (wasBlocked || mutated) ? 1 : 0),
        mutationRevision: state.mutationRevision + (mutated ? 1 : 0),
      ),
    );
  }

  Future<ApiError?> setBlocked(String id, bool blocked) async {
    if (isClosed || state.pending.contains(id)) return null;
    if (follow.state.pending.contains(id)) {
      return ApiError(
        message: 'Wait for this user’s follow request to finish.',
      );
    }
    _pending(id, true);
    try {
      final user = await repo.setBlocked(id, blocked);
      if (isClosed) return null;
      if (user.id != id || user.isBlocked != blocked) {
        throw ApiError(
          message: 'The server did not confirm the requested block state',
        );
      }
      _commit(id, blocked, user: user, mutated: true);
      return null;
    } catch (e) {
      return _error(e);
    } finally {
      if (!isClosed) _pending(id, false);
    }
  }

  Future<ApiError?> checkStatus(String id) async {
    if (isClosed || state.pending.contains(id)) return null;
    if (follow.state.pending.contains(id)) {
      return ApiError(
        message: 'Wait for this user’s follow request to finish.',
      );
    }
    _pending(id, true);
    try {
      final result = await repo.status(id);
      if (!isClosed) _commit(id, result.isBlocked);
      return null;
    } catch (e) {
      return _error(e);
    } finally {
      if (!isClosed) _pending(id, false);
    }
  }

  /// Reuses the user-list pagination Cubit. Late pages cannot undo a newer
  /// mutation/status result, nor publish stale follow counts during a request.
  Future<UsersPageModel> loadUsers(int page) async {
    final generation = page == 1 ? ++_listGeneration : _listGeneration;
    final revision = _revision;
    final followRevision = follow.state.revision;
    final result = await repo.users(page: page);
    if (!isClosed && generation == _listGeneration) {
      for (final user in result.users) {
        if (state.pending.contains(user.id) ||
            follow.state.pending.contains(user.id) ||
            (_versions[user.id] ?? 0) > revision) {
          continue;
        }
        _commit(
          user.id,
          true,
          user: followRevision == follow.state.revision
              ? user.copyWith(isBlocked: true)
              : null,
        );
      }
    }
    return result;
  }

  @override
  Future<void> close() {
    for (final id in state.pending) {
      follow.setBlockPending(id, false);
    }
    return super.close();
  }

  ApiError _error(Object e) => e is ApiError
      ? e
      : ApiError(message: 'Unable to update block status. Please try again.');
}
