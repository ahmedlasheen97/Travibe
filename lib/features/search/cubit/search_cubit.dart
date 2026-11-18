import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/material.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/search/data/recent_search.dart';
import 'package:travibe/features/search/data/search_repo.dart';

part 'search_state.dart';

class SearchCubit extends Cubit<SearchState> {
  SearchCubit({SearchRepo? repo})
    : _repo = repo ?? SearchRepo(),
      super(const SearchState()) {
    _preferences.addListener(_sessionChanged);
  }

  final SearchRepo _repo;
  final _preferences = PreferencesManager();
  final searchController = TextEditingController();

  Timer? _debounce;
  int _requestId = 0;
  int _currentPage = 0;
  int? _paginationRequestId;

  /// Owner of the loaded recents; null until resolved for this session.
  String? _recentsOwner;
  Future<String?>? _recentsLoad;

  /// Loads the signed-in account's history. Safe to call repeatedly.
  Future<void> loadRecents() => _ensureRecents();

  Future<String?> _ensureRecents() {
    final session = _preferences.sessionRevision;
    return _recentsLoad ??= () async {
      try {
        final owner = await _repo.getCurrentUserId();
        if (isClosed || session != _preferences.sessionRevision) return null;
        _recentsOwner = owner;
        emit(state.copyWith(recentSearches: _repo.getRecentSearches(owner)));
        return owner;
      } catch (_) {
        // No history is better than another account's; retry on next use.
        if (session == _preferences.sessionRevision) _recentsLoad = null;
        return null;
      }
    }();
  }

  void _sessionChanged() {
    if (isClosed) return;
    _recentsOwner = null;
    _recentsLoad = null;
    emit(state.copyWith(recentSearches: const []));
    if (_preferences.hasSession) loadRecents();
  }

  // ---------------- typing / searching ----------------

  void onQueryChanged(String value) {
    _debounce?.cancel();
    _requestId++; // anything still in flight is now stale
    _paginationRequestId = null;

    final query = value.trim();

    if (query.isEmpty) {
      emit(
        state.copyWith(
          query: '',
          status: SearchStatus.idle,
          people: const [],
          hasMorePeople: false,
          isLoadingMore: false,
          errorMessage: '',
          paginationError: '',
        ),
      );
      return;
    }

    // Typing "@..." means looking for a person.
    final tab = query.startsWith('@') ? SearchTab.people : state.tab;
    final next = state.copyWith(query: query, tab: tab);

    if (!next.canSearch) {
      emit(
        next.copyWith(
          status: SearchStatus.idle,
          people: const [],
          hasMorePeople: false,
          isLoadingMore: false,
          errorMessage: '',
          paginationError: '',
        ),
      );
      return;
    }

    emit(
      next.copyWith(
        status: SearchStatus.loading,
        people: const [],
        hasMorePeople: false,
        isLoadingMore: false,
        errorMessage: '',
        paginationError: '',
      ),
    );
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _search(next.searchTerm),
    );
  }

  /// Keyboard "search" button: search immediately and remember the query.
  void submit() {
    _debounce?.cancel();
    if (!state.canSearch) return;

    _addRecent(RecentSearch(state.query));
    _search(state.searchTerm);
  }

  Future<void> retry() {
    _debounce?.cancel();
    return _search(state.searchTerm);
  }

  Future<void> _search(String term) async {
    if (isClosed || !state.canSearch) return;
    final requestId = ++_requestId;
    _paginationRequestId = null;
    emit(
      state.copyWith(
        status: SearchStatus.loading,
        errorMessage: '',
        paginationError: '',
        isLoadingMore: false,
      ),
    );

    try {
      final page = await _repo.searchUsers(term, page: 1);
      if (requestId != _requestId || isClosed) return;

      _currentPage = page.currentPage;
      emit(
        state.copyWith(
          status: SearchStatus.loaded,
          people: {
            for (final user in page.users) user.id: user,
          }.values.toList(),
          hasMorePeople: page.hasMore,
          isLoadingMore: false,
        ),
      );
    } catch (e) {
      if (requestId != _requestId || isClosed) return;
      emit(
        state.copyWith(
          status: SearchStatus.failure,
          errorMessage: _messageFrom(e),
        ),
      );
    }
  }

  Future<void> loadMorePeople({bool retry = false}) async {
    if (isClosed ||
        _paginationRequestId == _requestId ||
        (!retry && state.paginationError.isNotEmpty) ||
        !state.hasMorePeople ||
        state.status != SearchStatus.loaded) {
      return;
    }

    final requestId = _requestId;
    _paginationRequestId = requestId;
    emit(state.copyWith(isLoadingMore: true, paginationError: ''));

    try {
      final page = await _repo.searchUsers(
        state.searchTerm,
        page: _currentPage + 1,
      );
      if (requestId != _requestId || isClosed) return;

      _currentPage = page.currentPage;
      final people = {for (final user in state.people) user.id: user};
      for (final user in page.users) {
        people[user.id] = user;
      }
      emit(
        state.copyWith(
          people: people.values.toList(),
          hasMorePeople: page.hasMore,
          isLoadingMore: false,
        ),
      );
    } catch (error) {
      if (requestId == _requestId && !isClosed) {
        emit(
          state.copyWith(
            isLoadingMore: false,
            paginationError: _messageFrom(error),
          ),
        );
      }
    } finally {
      if (_paginationRequestId == requestId) _paginationRequestId = null;
    }
  }

  void clearQuery() {
    searchController.clear();
    onQueryChanged('');
  }

  void setTab(SearchTab tab) => emit(state.copyWith(tab: tab));

  // ---------------- recent searches ----------------

  /// Fills the field with a query recent and runs it. Person recents are
  /// opened by the screen; see [touchRecent].
  void selectRecent(RecentSearch recent) {
    final value = recent.text;
    searchController.text = value;
    searchController.selection = TextSelection.collapsed(offset: value.length);
    onQueryChanged(value);
    submit();
  }

  /// Remembers a person the user opened from the results as "@username".
  Future<void> recordPerson(PublicUserModel user) {
    final handle = user.handle.isNotEmpty ? user.handle : user.name.trim();
    if (handle.isEmpty) return Future.value();
    return _addRecent(RecentSearch(handle, userId: user.id));
  }

  /// Moves an existing recent to the top (e.g. a person row was reopened).
  Future<void> touchRecent(RecentSearch recent) => _addRecent(recent);

  Future<void> _addRecent(RecentSearch recent) => _updateRecents(
    (current) => [
      recent,
      ...current.where((item) => !item.sameText(recent)),
    ].take(SearchRepo.maxRecent).toList(),
  );

  Future<void> removeRecent(RecentSearch recent) => _updateRecents(
    (current) => current.where((item) => !item.sameText(recent)).toList(),
  );

  Future<void> clearRecents() => _updateRecents((_) => const []);

  Future<void> _updateRecents(
    List<RecentSearch> Function(List<RecentSearch> current) change,
  ) async {
    final session = _preferences.sessionRevision;
    final owner = _recentsOwner ?? await _ensureRecents();
    if (owner == null ||
        isClosed ||
        session != _preferences.sessionRevision ||
        owner != _recentsOwner) {
      return;
    }
    final updated = change(state.recentSearches);
    emit(state.copyWith(recentSearches: updated));
    try {
      await _repo.saveRecentSearches(owner, updated);
    } catch (_) {
      // Local history persistence must not interrupt a successful search.
    }
  }

  String _messageFrom(Object e) =>
      e is ApiError ? e.message : 'Unable to search people. Please try again.';

  @override
  Future<void> close() {
    _debounce?.cancel();
    _preferences.removeListener(_sessionChanged);
    searchController.dispose();
    return super.close();
  }
}
