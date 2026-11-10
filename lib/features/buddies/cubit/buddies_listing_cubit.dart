import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import '../data/buddies_filters.dart';
import '../data/buddies_home_response.dart';
import '../data/buddies_page.dart';
import '../data/buddies_repo.dart';

class BuddiesListingState {
  BuddiesListingState({
    List<BuddyResource> items = const [],
    required this.filters,
    this.page,
    this.loading = false,
    this.error,
    this.refreshing = false,
  }) : items = List.unmodifiable(items);
  final List<BuddyResource> items;
  final BuddiesFilters filters;
  final BuddiesPage? page;
  final bool loading;
  final bool refreshing;
  final ApiError? error;
}

class BuddiesListingCubit extends Cubit<BuddiesListingState> {
  BuddiesListingCubit({required this.listing, BuddiesRepo? repo})
    : _repo = repo ?? BuddiesRepo(),
      super(BuddiesListingState(filters: BuddiesFilters())) {
    _preferences.addListener(_sessionChanged);
  }
  final BuddiesListing listing;
  final BuddiesRepo _repo;
  final _preferences = PreferencesManager();
  int _generation = 0;
  Future<void>? _pending;
  final Set<String> _visited = {};
  final Set<int> _pages = {};

  void _sessionChanged() {
    ++_generation;
    _pending = null;
    _visited.clear();
    _pages.clear();
    emit(BuddiesListingState(filters: BuddiesFilters()));
    refresh();
  }

  Future<void> apply(BuddiesFilters filters) async {
    if (isClosed || filters == state.filters) return;
    ++_generation;
    _pending = null;
    emit(BuddiesListingState(filters: filters));
    await refresh();
  }

  Future<void> refresh() => _load(reset: true);
  Future<void> loadMore() => _load(reset: false);

  Future<void> _load({required bool reset}) {
    if (isClosed) return Future.value();
    if (_pending != null) return reset ? _pending! : Future.value();
    if (!reset &&
        (state.page?.next == null || state.page?.hasCurrentCity == false)) {
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
    final next = reset ? null : state.page!.next;
    final generation = reset ? ++_generation : _generation;
    final session = _preferences.sessionRevision;
    if (reset) {
      _visited.clear();
      _pages.clear();
    }
    if (!_preferences.hasSession) {
      emit(
        BuddiesListingState(
          filters: state.filters,
          error: ApiError(
            message: 'Sign in to discover travelers.',
            statusCode: 401,
          ),
        ),
      );
      return;
    }
    final filters = state.filters;
    emit(
      BuddiesListingState(
        items: state.items,
        filters: filters,
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
          : BuddiesRepo.paginationKey(listing, next);
      if (nextKey != null && _visited.contains(nextKey)) {
        throw ApiError(
          message: 'Pagination did not advance. Pull down to refresh.',
        );
      }
      final page = await _repo.getListing(
        listing,
        filters: filters,
        next: next,
      );
      if (!current()) return;
      final returnedNext = page.next == null || page.hasCurrentCity == false
          ? null
          : BuddiesRepo.paginationKey(listing, page.next!);
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
      emit(
        BuddiesListingState(
          items: page.hasCurrentCity == false ? [] : byId.values.toList(),
          filters: filters,
          page: page,
        ),
      );
    } catch (error) {
      if (!current()) return;
      final failure = error is ApiError
          ? error
          : ApiError(message: 'Unable to load travelers. Please try again.');
      final denied = [401, 403].contains(failure.statusCode);
      emit(
        BuddiesListingState(
          items: denied ? [] : state.items,
          filters: filters,
          page: denied ? null : state.page,
          error: failure,
          refreshing: reset,
        ),
      );
    }
  }

  @override
  Future<void> close() {
    ++_generation;
    _preferences.removeListener(_sessionChanged);
    return super.close();
  }
}
