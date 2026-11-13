import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/data/follow_errors.dart';
import 'package:travibe/features/follow_requests/data/follow_requests_repo.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';

class IncomingRequestsState {
  IncomingRequestsState({
    Set<String> ids = const {},
    Set<String> handled = const {},
    Set<String> pending = const {},
    this.total = 0,
    this.loaded = false,
  }) : ids = Set.unmodifiable(ids),
       handled = Set.unmodifiable(handled),
       pending = Set.unmodifiable(pending);

  /// Requesters known to be waiting (first page of `GET follow-requests`).
  final Set<String> ids;

  /// Requests accepted/declined in this session; hidden everywhere.
  final Set<String> handled;

  /// Accept/decline calls in flight.
  final Set<String> pending;

  /// `meta.total` of pending requests, adjusted optimistically.
  final int total;
  final bool loaded;

  bool contains(String id) => ids.contains(id) && !handled.contains(id);
  bool isHandled(String id) => handled.contains(id);
}

/// Root-scoped view of follow requests sent *to* me. Drives the Settings
/// count, the profile "Requested to follow you." card, the Follow Requests
/// screen and inline notification actions so they all agree.
class IncomingRequestsCubit extends Cubit<IncomingRequestsState> {
  IncomingRequestsCubit({
    FollowRequestsRepo? repo,
    this.follow,
    this.currentUser,
  }) : repo = repo ?? FollowRequestsRepo(),
       super(IncomingRequestsState()) {
    _preferences.addListener(_sessionChanged);
  }

  final FollowRequestsRepo repo;
  final FollowCubit? follow;

  /// Resolved lazily: Root sits below the app-level [CurrentUserCubit].
  final CurrentUserCubit? Function()? currentUser;
  final _preferences = PreferencesManager();
  int _generation = 0;
  Future<void>? _syncing;

  static const syncPageSize = 100;

  void _sessionChanged() {
    ++_generation;
    _syncing = null;
    if (!isClosed) emit(IncomingRequestsState());
  }

  bool _current(int generation) => !isClosed && generation == _generation;

  @override
  Future<void> close() {
    ++_generation;
    _preferences.removeListener(_sessionChanged);
    return super.close();
  }

  bool contains(String id) => state.contains(id);

  /// Reloads the first page of requests (ids + total). Joins a running sync.
  Future<void> sync() {
    if (isClosed || !_preferences.hasSession) return Future.value();
    return _syncing ??= _sync().whenComplete(() => _syncing = null);
  }

  Future<void> _sync() async {
    final generation = _generation;
    try {
      final page = await repo.list(perPage: syncPageSize);
      if (!_current(generation)) return;
      final ids = {for (final user in page.users) user.id};
      emit(
        IncomingRequestsState(
          ids: ids,
          // Server truth replaces optimistic removals except in-flight ones.
          handled: state.handled.intersection(state.pending),
          pending: state.pending,
          total: page.total,
          loaded: true,
        ),
      );
    } catch (_) {
      // Keep the last known state; screens surface their own load errors.
    }
  }

  /// Records requesters seen on the Follow Requests screen (later pages).
  void remember(Iterable<String> ids, {int? total}) {
    if (isClosed) return;
    final next = {...state.ids, ...ids};
    if (next.length == state.ids.length && total == null) return;
    emit(
      IncomingRequestsState(
        ids: next,
        handled: state.handled,
        pending: state.pending,
        total: total ?? state.total,
        loaded: state.loaded,
      ),
    );
  }

  Future<ApiError?> accept(String id) => _resolve(id, accept: true);
  Future<ApiError?> decline(String id) => _resolve(id, accept: false);

  Future<ApiError?> _resolve(String id, {required bool accept}) async {
    if (isClosed || state.pending.contains(id) || state.handled.contains(id)) {
      return null;
    }
    final generation = _generation;
    final before = state;
    final wasListed = before.ids.contains(id);
    // Optimistic: hide the request everywhere immediately.
    emit(
      IncomingRequestsState(
        ids: {...before.ids, id},
        handled: {...before.handled, id},
        pending: {...before.pending, id},
        total: wasListed || before.total > 0
            ? (before.total - 1).clamp(0, 1 << 31).toInt()
            : 0,
        loaded: before.loaded,
      ),
    );
    if (accept) currentUser?.call()?.adjustFollowersCount(1);
    try {
      if (accept) {
        final user = await repo.accept(id);
        if (!_current(generation)) return null;
        follow?.markFollowsYou(id, user: user.id == id ? user : null);
      } else {
        await repo.decline(id);
        if (!_current(generation)) return null;
      }
      _finish(id);
      return null;
    } catch (error) {
      if (!_current(generation)) return null;
      final mapped = followError(error);
      if (mapped.statusCode == 409 || mapped.statusCode == 404) {
        // Already accepted/declined/cancelled elsewhere: stay removed, but
        // the follower count is unknown — let the server decide.
        if (accept) currentUser?.call()?.adjustFollowersCount(-1);
        _finish(id);
        sync();
        return mapped;
      }
      if (accept) currentUser?.call()?.adjustFollowersCount(-1);
      emit(
        IncomingRequestsState(
          ids: state.ids,
          handled: {...state.handled}..remove(id),
          pending: {...state.pending}..remove(id),
          total: state.total + 1,
          loaded: state.loaded,
        ),
      );
      return mapped;
    }
  }

  void _finish(String id) => emit(
    IncomingRequestsState(
      ids: state.ids,
      handled: state.handled,
      pending: {...state.pending}..remove(id),
      total: state.total,
      loaded: state.loaded,
    ),
  );
}
