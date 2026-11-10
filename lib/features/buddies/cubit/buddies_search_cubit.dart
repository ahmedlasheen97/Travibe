import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/places/city_places_provider.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import '../data/buddies_filters.dart';
import '../data/buddies_home_response.dart';
import '../data/buddies_page.dart';
import '../data/buddies_repo.dart';
import '../data/buddies_search_query.dart';

class BuddiesSearchState {
  BuddiesSearchState({
    this.text = '',
    BuddiesFilters? filters,
    this.selectedCity,
    List<BuddyResource> items = const [],
    this.page,
    this.loading = false,
    this.error,
    this.recentError,
    this.refreshing = false,
  }) : filters = filters ?? BuddiesFilters(),
       items = List.unmodifiable(items);
  final String text;
  final BuddiesFilters filters;
  final CitySelection? selectedCity;
  String? get countryCode => selectedCity?.countryCode;
  final List<BuddyResource> items;
  final BuddiesPage? page;
  final bool loading;
  final ApiError? error;
  final ApiError? recentError;
  final bool refreshing;
  BuddiesSearchQuery? get query {
    if (selectedCity == null) return null;
    try {
      return BuddiesSearchQuery(
        city: selectedCity!.cityName,
        filters: filters,
        countryCode: countryCode,
      );
    } on ArgumentError {
      return null;
    }
  }

  BuddiesSearchState results({
    List<BuddyResource> items = const [],
    BuddiesPage? page,
    bool loading = false,
    ApiError? error,
    String? text,
    bool refreshing = false,
  }) => BuddiesSearchState(
    text: text ?? this.text,
    filters: filters,
    selectedCity: selectedCity,
    items: items,
    page: page,
    loading: loading,
    error: error,
    recentError: recentError,
    refreshing: refreshing,
  );
}

class BuddiesSearchCubit extends Cubit<BuddiesSearchState> {
  BuddiesSearchCubit({BuddiesRepo? repo})
    : _repo = repo ?? BuddiesRepo(),
      super(BuddiesSearchState()) {
    _preferences.addListener(_sessionChanged);
  }
  final BuddiesRepo _repo;
  final _preferences = PreferencesManager();
  Future<void>? _pending;
  int _generation = 0;
  final Set<String> _visited = {};
  final Set<int> _pages = {};

  void _invalidate() {
    ++_generation;
    _pending = null;
    _visited.clear();
    _pages.clear();
  }

  void _sessionChanged() {
    _invalidate();
    // Account changes discard the old account's query and filter selections.
    emit(BuddiesSearchState());
  }

  /// Unresolved input must never issue a people-discovery request.
  void setCity(String text) {
    if (isClosed || (text == state.text && state.selectedCity == null)) return;
    _invalidate();
    emit(BuddiesSearchState(text: text, filters: state.filters));
  }

  void selectCity(CitySelection city) {
    if (isClosed ||
        identical(city, state.selectedCity) ||
        city.cityName == state.selectedCity?.cityName &&
            city.countryCode == state.selectedCity?.countryCode) {
      return;
    }
    _replace(
      BuddiesSearchState(
        text: city.label,
        selectedCity: city,
        filters: state.filters,
      ),
    );
    unawaited(_saveRecent(city));
  }

  Future<void> _saveRecent(CitySelection city) async {
    final generation = _generation;
    final session = _preferences.sessionRevision;
    try {
      if (!_preferences.hasSession) return;
      await _repo.saveRecentDestination(city.label);
    } catch (error) {
      if (isClosed ||
          generation != _generation ||
          session != _preferences.sessionRevision) {
        return;
      }
      emit(
        BuddiesSearchState(
          text: state.text,
          selectedCity: state.selectedCity,
          filters: state.filters,
          items: state.items,
          page: state.page,
          loading: state.loading,
          refreshing: state.refreshing,
          error: state.error,
          recentError: error is ApiError
              ? error
              : ApiError(message: 'Recent destination could not be saved.'),
        ),
      );
    }
  }

  void apply(BuddiesFilters filters) {
    if (isClosed || filters == state.filters) return;
    _replace(
      BuddiesSearchState(
        text: state.text,
        selectedCity: state.selectedCity,
        filters: filters,
      ),
    );
  }

  void _replace(BuddiesSearchState next) {
    _invalidate();
    emit(next);
    if (next.query != null) refresh();
  }

  Future<void> refresh() => _load(reset: true);
  Future<void> loadMore() => _load(reset: false);

  Future<void> _load({required bool reset}) {
    if (isClosed || state.query == null) return Future.value();
    if (_pending != null) return reset ? _pending! : Future.value();
    if (!reset && (state.page?.next == null)) {
      return Future.value();
    }
    final request = _fetch(reset: reset);
    final generation = _generation;
    _pending = request;
    return request.whenComplete(() {
      if (generation == _generation) _pending = null;
    });
  }

  Future<void> _fetch({required bool reset}) async {
    final query = state.query!;
    final next = reset ? null : state.page!.next;
    final generation = reset ? ++_generation : _generation;
    final session = _preferences.sessionRevision;
    if (reset) {
      _visited.clear();
      _pages.clear();
    }
    if (!_preferences.hasSession) {
      emit(
        state.results(
          error: ApiError(
            message: 'Sign in to search travelers.',
            statusCode: 401,
          ),
        ),
      );
      return;
    }
    emit(
      state.results(
        items: state.items,
        page: state.page,
        refreshing: reset,
        loading: true,
      ),
    );
    bool current() =>
        !isClosed &&
        generation == _generation &&
        session == _preferences.sessionRevision;
    try {
      final nextKey = next == null
          ? null
          : BuddiesRepo.searchPaginationKey(next);
      if (nextKey != null && _visited.contains(nextKey)) {
        throw ApiError(
          message: 'Pagination did not advance. Pull down to refresh.',
        );
      }
      final page = await _repo.search(query: query, next: next);
      if (!current()) return;
      final returnedNext = page.next == null
          ? null
          : BuddiesRepo.searchPaginationKey(page.next!);
      if (_pages.contains(page.currentPage) ||
          (!reset && page.currentPage <= state.page!.currentPage) ||
          returnedNext != null &&
              (_visited.contains(returnedNext) || returnedNext == nextKey)) {
        throw ApiError(
          message: 'Pagination did not advance. Pull down to refresh.',
        );
      }
      _pages.add(page.currentPage);
      if (nextKey != null) _visited.add(nextKey);
      final byId = {
        if (!reset)
          for (final item in state.items) item.id: item,
      };
      for (final item in page.items) {
        byId.putIfAbsent(item.id, () => item);
      }
      emit(state.results(items: byId.values.toList(), page: page));
    } catch (error) {
      if (!current()) return;
      final failure = error is ApiError
          ? error
          : ApiError(message: 'Unable to search travelers. Please try again.');
      final denied = [401, 403].contains(failure.statusCode);
      emit(
        state.results(
          items: denied ? [] : state.items,
          page: denied ? null : state.page,
          error: failure,
          refreshing: reset,
        ),
      );
    }
  }

  @override
  Future<void> close() {
    _invalidate();
    _preferences.removeListener(_sessionChanged);
    return super.close();
  }
}
