import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/material.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/search/data/search_repo.dart';

part 'search_state.dart';

class SearchCubit extends Cubit<SearchState> {
  SearchCubit({SearchRepo? repo})
    : _repo = repo ?? SearchRepo(),
      super(const SearchState());

  final SearchRepo _repo;
  final searchController = TextEditingController();

  Timer? _debounce;
  int _requestId = 0;
  int _currentPage = 0;
  int? _paginationRequestId;

  void loadRecents() {
    emit(state.copyWith(recentSearches: _repo.getRecentSearches()));
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

    _addRecent(state.query);
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

  void selectRecent(String value) {
    searchController.text = value;
    searchController.selection = TextSelection.collapsed(offset: value.length);
    onQueryChanged(value);
    submit();
  }

  Future<void> _addRecent(String query) async {
    final updated = [
      query,
      ...state.recentSearches.where(
        (s) => s.toLowerCase() != query.toLowerCase(),
      ),
    ].take(SearchRepo.maxRecent).toList();

    emit(state.copyWith(recentSearches: updated));
    await _saveRecents(updated);
  }

  Future<void> removeRecent(String value) async {
    final updated = state.recentSearches.where((s) => s != value).toList();
    emit(state.copyWith(recentSearches: updated));
    await _saveRecents(updated);
  }

  Future<void> clearRecents() async {
    emit(state.copyWith(recentSearches: const []));
    await _saveRecents(const []);
  }

  Future<void> _saveRecents(List<String> values) async {
    try {
      await _repo.saveRecentSearches(values);
    } catch (_) {
      // Local history persistence must not interrupt a successful search.
    }
  }

  String _messageFrom(Object e) =>
      e is ApiError ? e.message : 'Unable to search people. Please try again.';

  @override
  Future<void> close() {
    _debounce?.cancel();
    searchController.dispose();
    return super.close();
  }
}
