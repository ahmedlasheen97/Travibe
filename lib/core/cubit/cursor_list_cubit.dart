import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/cursor_pagination.dart';

enum CursorListStatus { initial, loading, loaded, failure }

class CursorListState<T> {
  CursorListState({
    this.status = CursorListStatus.initial,
    Iterable<T> items = const [],
    this.hasMore = false,
    this.refreshing = false,
    this.loadingMore = false,
    this.error,
    this.paginationError,
  }) : items = List.unmodifiable(items);
  final CursorListStatus status;
  final List<T> items;
  final bool hasMore, refreshing, loadingMore;
  final ApiError? error, paginationError;
}

/// Scope is immutable; use a fresh instance when author, target or filters change.
class CursorListCubit<T> extends Cubit<CursorListState<T>> {
  CursorListCubit({required this.loadPage, required this.idOf})
    : super(CursorListState<T>()) {
    _session.addListener(_sessionChanged);
  }
  final Future<CursorPage<T>> Function(String? cursor) loadPage;
  final Object Function(T item) idOf;
  final _session = PreferencesManager();
  final _progress = CursorProgress();
  int _generation = 0;
  Future<void>? _first;
  bool _more = false;
  String? get nextCursor => _progress.nextCursor;
  String? get prevCursor => _progress.prevCursor;

  void _sessionChanged() {
    ++_generation;
    _first = null;
    _more = false;
    _progress.clear();
    if (!isClosed) emit(CursorListState<T>());
  }

  Future<void> load() {
    if (isClosed) return Future.value();
    if (_first != null) return _first!;
    final request = _fetch(reset: true);
    _first = request;
    return request.whenComplete(() {
      if (identical(_first, request)) _first = null;
    });
  }

  Future<void> refresh() => load();

  Future<void> more({bool retry = false}) async {
    if (isClosed ||
        _first != null ||
        _more ||
        state.status != CursorListStatus.loaded ||
        !_progress.hasMore ||
        (state.paginationError != null && !retry)) {
      return;
    }
    await _fetch(reset: false);
  }

  Future<void> _fetch({required bool reset}) async {
    final generation = reset ? ++_generation : _generation;
    if (reset) _more = false;
    if (!reset) _more = true;
    final previous = state;
    final cursor = reset ? null : _progress.nextCursor;
    emit(
      CursorListState<T>(
        status: previous.status == CursorListStatus.loaded
            ? CursorListStatus.loaded
            : CursorListStatus.loading,
        items: previous.items,
        hasMore: previous.hasMore,
        refreshing: reset && previous.status == CursorListStatus.loaded,
        loadingMore: !reset,
      ),
    );
    try {
      final page = await loadPage(cursor);
      if (isClosed || generation != _generation) return;
      final items = <Object, T>{
        if (!reset)
          for (final item in state.items) idOf(item): item,
        for (final item in page.items) idOf(item): item,
      };
      _progress.accept(page.pagination, requestedCursor: cursor);
      emit(
        CursorListState<T>(
          status: CursorListStatus.loaded,
          items: items.values,
          hasMore: _progress.hasMore,
        ),
      );
    } catch (e) {
      if (isClosed || generation != _generation) return;
      final error = e is ApiError
          ? e
          : ApiError(message: 'Unable to load results. Please try again.');
      emit(
        CursorListState<T>(
          status: previous.status == CursorListStatus.loaded
              ? CursorListStatus.loaded
              : CursorListStatus.failure,
          items: previous.items,
          hasMore: previous.hasMore,
          error: reset ? error : previous.error,
          paginationError: reset ? previous.paginationError : error,
        ),
      );
    } finally {
      if (generation == _generation) _more = false;
    }
  }

  /// Reconcile cached rows after reconnect without discarding loaded pages or
  /// advancing the user's pagination cursor. REST remains authoritative.
  Future<void> reconcileCachedPages() async {
    if (isClosed) return;
    final session = _session.sessionRevision;
    if (state.items.isEmpty) {
      final pending = _first;
      if (pending != null) await pending;
      if (isClosed || session != _session.sessionRevision) return;
      if (state.items.isEmpty) return load();
    }
    final generation = ++_generation;
    _first = null;
    _more = false;
    final previous = state;
    final oldest = idOf(previous.items.last);
    final updated = <Object, T>{};
    final cursors = <String?>{};
    String? cursor;
    try {
      do {
        if (!cursors.add(cursor)) {
          throw const FormatException('Repeated cursor.');
        }
        final page = await loadPage(cursor);
        if (isClosed || generation != _generation) return;
        for (final item in page.items) {
          updated[idOf(item)] = item;
        }
        if (updated.containsKey(oldest)) break;
        cursor = page.pagination.nextCursor;
      } while (cursor != null);
      if (isClosed || generation != _generation) return;
      final merged = <Object, T>{
        ...updated,
        for (final item in state.items)
          if (!updated.containsKey(idOf(item))) idOf(item): item,
      };
      emit(
        CursorListState(
          status: CursorListStatus.loaded,
          items: merged.values,
          hasMore: previous.hasMore,
        ),
      );
    } catch (e) {
      if (!isClosed && generation == _generation) {
        emit(
          CursorListState(
            status: previous.status,
            items: state.items,
            hasMore: previous.hasMore,
            error: e is ApiError
                ? e
                : ApiError(
                    message:
                        'Unable to synchronize notifications. Please retry.',
                  ),
          ),
        );
      }
    }
  }

  @override
  Future<void> close() {
    ++_generation;
    _session.removeListener(_sessionChanged);
    return super.close();
  }
}
