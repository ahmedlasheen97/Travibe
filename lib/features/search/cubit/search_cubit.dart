import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/material.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/home/data/post_model.dart';
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
  int _peopleRequest = 0, _postsRequest = 0;
  int _peoplePage = 0, _postsPage = 0;
  int? _peoplePaginationRequest, _postsPaginationRequest;

  /// The term each tab's results belong to; null when stale or failed.
  String? _peopleTerm, _postsTerm;

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

  /// Drops both tabs' results (and makes anything in flight stale).
  SearchState _withoutResults(SearchState from) {
    _peopleRequest++;
    _postsRequest++;
    _peoplePaginationRequest = _postsPaginationRequest = null;
    _peopleTerm = _postsTerm = null;
    return from.copyWith(
      status: SearchStatus.idle,
      people: const [],
      hasMorePeople: false,
      isLoadingMore: false,
      errorMessage: '',
      paginationError: '',
      postsStatus: SearchStatus.idle,
      posts: const [],
      hasMorePosts: false,
      isLoadingMorePosts: false,
      postsError: '',
      postsPaginationError: '',
    );
  }

  void onQueryChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();

    if (query.isEmpty) {
      emit(_withoutResults(state).copyWith(query: ''));
      return;
    }

    // Typing "@..." means looking for a person.
    final tab = query.startsWith('@') ? SearchTab.people : state.tab;
    final next = _withoutResults(state.copyWith(query: query, tab: tab));
    if (!next.canSearch) {
      emit(next);
      return;
    }

    // Show the active tab's loading state while the debounce runs.
    emit(
      next.tab == SearchTab.posts
          ? next.copyWith(postsStatus: SearchStatus.loading)
          : next.copyWith(status: SearchStatus.loading),
    );
    _debounce = Timer(const Duration(milliseconds: 400), () => _searchActive());
  }

  /// Keyboard "search" button: search immediately and remember the query.
  void submit() {
    _debounce?.cancel();
    if (!state.canSearch) return;

    _addRecent(RecentSearch(state.query));
    _searchActive();
  }

  /// Re-runs the visible tab's search.
  Future<void> retry() {
    _debounce?.cancel();
    return _searchActive();
  }

  Future<void> _searchActive() => state.tab == SearchTab.posts
      ? _searchPosts(state.searchTerm)
      : _searchPeople(state.searchTerm);

  void setTab(SearchTab tab) {
    if (tab == state.tab) return;
    emit(state.copyWith(tab: tab));
    // A pending debounce will search the new tab when it fires.
    if (_debounce?.isActive == true || !state.canSearch) return;
    final term = state.searchTerm;
    if (tab == SearchTab.posts && _postsTerm != term) _searchPosts(term);
    if (tab == SearchTab.people && _peopleTerm != term) _searchPeople(term);
  }

  // ---------------- people ----------------

  Future<void> _searchPeople(String term) async {
    if (isClosed || !state.canSearch) return;
    final requestId = ++_peopleRequest;
    _peoplePaginationRequest = null;
    _peopleTerm = term;
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
      if (requestId != _peopleRequest || isClosed) return;

      _peoplePage = page.currentPage;
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
      if (requestId != _peopleRequest || isClosed) return;
      _peopleTerm = null;
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
        _peoplePaginationRequest == _peopleRequest ||
        (!retry && state.paginationError.isNotEmpty) ||
        !state.hasMorePeople ||
        state.status != SearchStatus.loaded) {
      return;
    }

    final requestId = _peopleRequest;
    _peoplePaginationRequest = requestId;
    emit(state.copyWith(isLoadingMore: true, paginationError: ''));

    try {
      final page = await _repo.searchUsers(
        state.searchTerm,
        page: _peoplePage + 1,
      );
      if (requestId != _peopleRequest || isClosed) return;

      _peoplePage = page.currentPage;
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
      if (requestId == _peopleRequest && !isClosed) {
        emit(
          state.copyWith(
            isLoadingMore: false,
            paginationError: _messageFrom(error),
          ),
        );
      }
    } finally {
      if (_peoplePaginationRequest == requestId) {
        _peoplePaginationRequest = null;
      }
    }
  }

  // ---------------- posts ----------------

  Future<void> _searchPosts(String term) async {
    if (isClosed || !state.canSearch) return;
    final requestId = ++_postsRequest;
    _postsPaginationRequest = null;
    _postsTerm = term;
    emit(
      state.copyWith(
        postsStatus: SearchStatus.loading,
        posts: const [],
        hasMorePosts: false,
        postsError: '',
        postsPaginationError: '',
        isLoadingMorePosts: false,
      ),
    );

    try {
      final page = await _repo.searchPosts(term);
      if (requestId != _postsRequest || isClosed) return;

      _postsPage = page.currentPage;
      emit(
        state.copyWith(
          postsStatus: SearchStatus.loaded,
          posts: {for (final post in page.posts) post.id: post}.values.toList(),
          hasMorePosts: page.hasMore,
        ),
      );
    } catch (e) {
      if (requestId != _postsRequest || isClosed) return;
      _postsTerm = null;
      emit(
        state.copyWith(
          postsStatus: SearchStatus.failure,
          postsError: _messageFrom(e, posts: true),
        ),
      );
    }
  }

  Future<void> loadMorePosts({bool retry = false}) async {
    if (isClosed ||
        _postsPaginationRequest == _postsRequest ||
        (!retry && state.postsPaginationError.isNotEmpty) ||
        !state.hasMorePosts ||
        state.postsStatus != SearchStatus.loaded) {
      return;
    }

    final requestId = _postsRequest;
    _postsPaginationRequest = requestId;
    emit(state.copyWith(isLoadingMorePosts: true, postsPaginationError: ''));

    try {
      final page = await _repo.searchPosts(
        state.searchTerm,
        page: _postsPage + 1,
      );
      if (requestId != _postsRequest || isClosed) return;

      _postsPage = page.currentPage;
      final posts = {for (final post in state.posts) post.id: post};
      for (final post in page.posts) {
        posts.putIfAbsent(post.id, () => post);
      }
      emit(
        state.copyWith(
          posts: posts.values.toList(),
          hasMorePosts: page.hasMore,
          isLoadingMorePosts: false,
        ),
      );
    } catch (error) {
      if (requestId == _postsRequest && !isClosed) {
        emit(
          state.copyWith(
            isLoadingMorePosts: false,
            postsPaginationError: _messageFrom(error, posts: true),
          ),
        );
      }
    } finally {
      if (_postsPaginationRequest == requestId) _postsPaginationRequest = null;
    }
  }

  void clearQuery() {
    searchController.clear();
    onQueryChanged('');
  }

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

  String _messageFrom(Object e, {bool posts = false}) => e is ApiError
      ? e.message
      : 'Unable to search ${posts ? 'posts' : 'people'}. Please try again.';

  @override
  Future<void> close() {
    _debounce?.cancel();
    _preferences.removeListener(_sessionChanged);
    searchController.dispose();
    return super.close();
  }
}
