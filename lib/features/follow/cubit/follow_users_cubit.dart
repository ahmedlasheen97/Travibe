import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';
import 'package:travibe/features/search/data/users_page_model.dart';

enum FollowUsersStatus { initial, loading, loaded, failure }

class FollowUsersState {
  FollowUsersState({
    this.status = FollowUsersStatus.initial,
    List<PublicUserModel> users = const [],
    this.hasMore = false,
    this.total,
    this.loadingMore = false,
    this.refreshing = false,
    this.error,
    this.paginationError,
  }) : users = List.unmodifiable(users);
  final FollowUsersStatus status;
  final List<PublicUserModel> users;
  final bool hasMore;
  final int? total;
  final bool loadingMore;
  final bool refreshing;
  final ApiError? error;
  final ApiError? paginationError;
}

class FollowUsersCubit extends Cubit<FollowUsersState> {
  FollowUsersCubit({
    this.type = FollowListType.suggested,
    this.userId,
    FollowRepo? repo,
    Future<UsersPageModel> Function(int page)? loadPage,
  }) : _loadPage = loadPage ?? _defaultLoader(repo, type, userId),
       super(FollowUsersState()) {
    PreferencesManager().addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (isClosed) return;
    ++_generation;
    _loading = null;
    _loadingMore = false;
    emit(FollowUsersState());
    if (PreferencesManager().hasSession) load();
  }

  @override
  Future<void> close() {
    PreferencesManager().removeListener(_sessionChanged);
    ++_generation;
    return super.close();
  }

  static Future<UsersPageModel> Function(int) _defaultLoader(
    FollowRepo? repo,
    FollowListType type,
    String? userId,
  ) {
    final source = repo ?? FollowRepo();
    return (page) => source.users(type: type, userId: userId, page: page);
  }

  final FollowListType type;
  final String? userId;
  final Future<UsersPageModel> Function(int page) _loadPage;
  Future<void> get pendingLoad => _loading ?? Future.value();
  int _page = 0;
  int _generation = 0;
  Future<void>? _loading;
  bool _loadingMore = false;

  Future<void> load({bool force = false}) {
    if (isClosed) return Future.value();
    if (!force && _loading != null) return _loading!;
    final request = _load();
    _loading = request;
    return request.whenComplete(() {
      if (identical(_loading, request)) _loading = null;
    });
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final previous = state;
    _loadingMore = false;
    emit(
      FollowUsersState(
        status: previous.status == FollowUsersStatus.loaded
            ? FollowUsersStatus.loaded
            : FollowUsersStatus.loading,
        users: previous.users,
        total: previous.total,
        hasMore: previous.hasMore,
        refreshing: previous.status == FollowUsersStatus.loaded,
      ),
    );
    try {
      final result = await _loadPage(1);
      if (isClosed || generation != _generation) return;
      _page = result.currentPage;
      emit(
        FollowUsersState(
          status: FollowUsersStatus.loaded,
          users: {
            for (final user in result.users) user.id: user,
          }.values.toList(),
          total: result.total,
          hasMore: result.hasMore,
        ),
      );
    } catch (e) {
      if (isClosed || generation != _generation) return;
      emit(
        FollowUsersState(
          status: previous.status == FollowUsersStatus.loaded
              ? FollowUsersStatus.loaded
              : FollowUsersStatus.failure,
          users: previous.users,
          total: previous.total,
          hasMore: previous.hasMore,
          error: _error(e),
        ),
      );
    }
  }

  Future<void> more({bool retry = false}) async {
    if (isClosed ||
        _loading != null ||
        _loadingMore ||
        state.status != FollowUsersStatus.loaded ||
        !state.hasMore ||
        (state.paginationError != null && !retry)) {
      return;
    }
    final generation = _generation;
    final previous = state;
    _loadingMore = true;
    emit(
      FollowUsersState(
        status: FollowUsersStatus.loaded,
        users: previous.users,
        total: previous.total,
        hasMore: previous.hasMore,
        loadingMore: true,
        error: previous.error,
      ),
    );
    try {
      final result = await _loadPage(_page + 1);
      if (isClosed || generation != _generation) return;
      _page = result.currentPage;
      final users = {for (final user in previous.users) user.id: user};
      for (final user in result.users) {
        users[user.id] = user;
      }
      emit(
        FollowUsersState(
          status: FollowUsersStatus.loaded,
          users: users.values.toList(),
          total: result.total,
          hasMore: result.hasMore,
          error: previous.error,
        ),
      );
    } catch (e) {
      if (isClosed || generation != _generation) return;
      emit(
        FollowUsersState(
          status: FollowUsersStatus.loaded,
          users: previous.users,
          total: previous.total,
          hasMore: previous.hasMore,
          paginationError: _error(e),
          error: previous.error,
        ),
      );
    } finally {
      if (generation == _generation) _loadingMore = false;
    }
  }

  /// Optimistically drops [id] from the loaded list (and one from [total]).
  /// Returns a restore callback that puts the row back at its old index; it
  /// is a no-op once a newer load has replaced the list.
  VoidCallback removeLocally(String id) {
    final previous = state;
    final index = previous.users.indexWhere((user) => user.id == id);
    if (isClosed || index < 0) return () {};
    final removed = previous.users[index];
    final generation = _generation;
    emit(
      _copy(
        previous,
        users: [...previous.users]..removeAt(index),
        total: previous.total == null
            ? null
            : (previous.total! - 1).clamp(0, previous.total!),
      ),
    );
    return () {
      if (isClosed || generation != _generation) return;
      if (state.users.any((user) => user.id == id)) return;
      final users = [...state.users];
      users.insert(index.clamp(0, users.length), removed);
      emit(
        _copy(
          state,
          users: users,
          total: state.total == null ? null : state.total! + 1,
        ),
      );
    };
  }

  FollowUsersState _copy(
    FollowUsersState s, {
    required List<PublicUserModel> users,
    required int? total,
  }) => FollowUsersState(
    status: s.status,
    users: users,
    hasMore: s.hasMore,
    total: total,
    loadingMore: s.loadingMore,
    refreshing: s.refreshing,
    error: s.error,
    paginationError: s.paginationError,
  );

  ApiError _error(Object e) => e is ApiError
      ? e
      : ApiError(message: 'Unable to load people. Please try again.');
}
