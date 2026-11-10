import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/search/data/search_repo.dart';

enum ChatDiscoveryStatus { idle, loading, loaded, failure }

class ChatDiscoveryState {
  const ChatDiscoveryState({
    this.query = '',
    this.status = ChatDiscoveryStatus.idle,
    this.users = const [],
    this.hasMore = false,
    this.loadingMore = false,
    this.filteredCount = 0,
    this.error,
  });
  final String query;
  final ChatDiscoveryStatus status;
  final List<PublicUserModel> users;
  final bool hasMore, loadingMore;
  final int filteredCount;
  final ApiError? error;
}

/// Uses the existing authenticated search repository. Responses belong to one
/// route/session and one query generation; old queries cannot publish results.
class ChatDiscoveryCubit extends Cubit<ChatDiscoveryState> {
  ChatDiscoveryCubit({
    SearchRepo? repo,
    String? currentUserId,
    this.delay = const Duration(milliseconds: 350),
  }) : _repo = repo ?? SearchRepo(),
       _identity = currentUserId,
       super(const ChatDiscoveryState()) {
    _preferences.addListener(_sessionChanged);
  }
  final SearchRepo _repo;
  final Duration delay;
  final _preferences = PreferencesManager();
  final _session = PreferencesManager().sessionRevision;
  String? _identity;
  Future<String>? _identityRequest;
  Timer? _timer;
  int _generation = 0, _page = 0;
  final Set<String> _blocked = {};
  bool get valid =>
      !isClosed &&
      _preferences.hasSession &&
      _session == _preferences.sessionRevision;

  void _sessionChanged() {
    ++_generation;
    _timer?.cancel();
    _identity = null;
    _identityRequest = null;
    if (!isClosed) emit(const ChatDiscoveryState());
  }

  void setBlocked(Set<String> ids) {
    _blocked
      ..clear()
      ..addAll(ids);
    if (!isClosed && state.status == ChatDiscoveryStatus.loaded) {
      emit(
        ChatDiscoveryState(
          query: state.query,
          status: state.status,
          users: state.users.where((u) => !_blocked.contains(u.id)).toList(),
          hasMore: state.hasMore,
          filteredCount: state.filteredCount,
          error: state.error,
        ),
      );
    }
  }

  void query(String value) {
    final term = value.trim();
    if (term == state.query && state.status != ChatDiscoveryStatus.failure) {
      return;
    }
    _timer?.cancel();
    ++_generation;
    final eligible = term.runes.length >= 3 && term.runes.length <= 100;
    emit(
      ChatDiscoveryState(
        query: term,
        status: eligible
            ? ChatDiscoveryStatus.loading
            : ChatDiscoveryStatus.idle,
      ),
    );
    if (!eligible || !valid) return;
    final generation = _generation;
    _timer = Timer(delay, () => _load(generation));
  }

  Future<void> retry() async {
    if (!valid ||
        state.query.runes.length < 3 ||
        state.query.runes.length > 100 ||
        state.status == ChatDiscoveryStatus.loading ||
        state.loadingMore) {
      return;
    }
    _timer?.cancel();
    await _load(++_generation);
  }

  Future<void> more() async {
    if (!valid ||
        !state.hasMore ||
        state.loadingMore ||
        state.status != ChatDiscoveryStatus.loaded) {
      return;
    }
    await _load(_generation, more: true);
  }

  Future<void> _load(int generation, {bool more = false}) async {
    if (!valid || generation != _generation) return;
    final previous = state;
    final term = state.query;
    emit(
      ChatDiscoveryState(
        query: term,
        status: more ? ChatDiscoveryStatus.loaded : ChatDiscoveryStatus.loading,
        users: more ? previous.users : const [],
        hasMore: previous.hasMore,
        loadingMore: more,
        filteredCount: previous.filteredCount,
      ),
    );
    try {
      final identity = _identity ??= await (_identityRequest ??= _repo
          .getCurrentUserId());
      if (!valid || generation != _generation) return;
      if (int.tryParse(identity) == null) {
        throw ApiError(
          message: 'Unable to identify your account. Please retry.',
        );
      }
      final page = await _repo.searchUsers(term, page: more ? _page + 1 : 1);
      if (!valid || generation != _generation) return;
      final expected = more ? _page + 1 : 1;
      if (page.currentPage != expected) {
        throw ApiError(
          message: 'Unable to read this search page. Please retry.',
        );
      }
      _page = page.currentPage;
      final candidates = page.users
          .where(
            (u) => u.id != identity && !u.isBlocked && !_blocked.contains(u.id),
          )
          .toList();
      final users = {
        if (more)
          for (final u in previous.users) u.id: u,
        for (final u in candidates) u.id: u,
      };
      emit(
        ChatDiscoveryState(
          query: term,
          status: ChatDiscoveryStatus.loaded,
          users: List.unmodifiable(
            users.values.where((u) => !_blocked.contains(u.id)),
          ),
          hasMore: page.hasMore,
          filteredCount: page.users.length - candidates.length,
        ),
      );
    } catch (error) {
      if (!valid || generation != _generation) return;
      _identityRequest = null;
      emit(
        ChatDiscoveryState(
          query: term,
          status: more
              ? ChatDiscoveryStatus.loaded
              : ChatDiscoveryStatus.failure,
          users: more ? previous.users : const [],
          hasMore: previous.hasMore,
          error: error is ApiError
              ? error
              : ApiError(message: 'Unable to search people. Please try again.'),
        ),
      );
    }
  }

  @override
  Future<void> close() {
    ++_generation;
    _timer?.cancel();
    _preferences.removeListener(_sessionChanged);
    return super.close();
  }
}
