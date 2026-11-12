import 'dart:async';
import 'package:travibe/core/cubit/cursor_list_cubit.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/models/cursor_pagination.dart';
import 'package:travibe/features/notifications/data/notifications_repo.dart';
import 'notification_activity.dart';

class NotificationsCubit extends CursorListCubit<Map<String, dynamic>> {
  NotificationsCubit({NotificationsRepo? repo, NotificationActivity? activity})
    : this._(repo ?? activity?.repository ?? NotificationsRepo(), activity);
  NotificationsCubit._(NotificationsRepo repo, NotificationActivity? activity)
    : super(
        loadPage: (cursor) => _withoutChatMessages(repo, cursor),
        idOf: (n) => n['id'] as Object,
      ) {
    _invalidations = activity?.invalidations.listen((session) {
      if (session == PreferencesManager().sessionRevision) {
        unawaited(_reconcile());
      }
    });
    _readEvents = activity?.reads.listen((event) {
      if (event.sessionRevision != PreferencesManager().sessionRevision) return;
      _checkSession();
      for (final id in event.ids) {
        if (event.reopened) {
          _read.remove(id);
        } else {
          _read[id] = event.at;
        }
      }
      _applyRead();
    });
  }

  /// Direct messages live in Chats; only message requests stay in the inbox
  /// (they are otherwise easy to miss in the Requests tab).
  static bool isChatMessage(Map<String, dynamic> item) =>
      item['type'] == 'message_received' &&
      !(item['data'] is Map && item['data']['is_request'] == true);

  /// Bounded so a long run of chat-only pages cannot spin; the cursor still
  /// lets `more()` continue from where this stopped.
  static const _maxSkippedPages = 5;
  static Future<CursorPage<Map<String, dynamic>>> _withoutChatMessages(
    NotificationsRepo repo,
    String? cursor,
  ) async {
    var page = await repo.list(cursor: cursor);
    var kept = page.items.where((n) => !isChatMessage(n)).toList();
    final seen = {cursor};
    // Only pages emptied by the filter are skipped; a server-empty page (or a
    // repeated cursor) goes back unchanged for CursorListCubit to handle.
    for (
      var skipped = 0;
      kept.isEmpty &&
          page.items.isNotEmpty &&
          page.hasMore &&
          seen.add(page.pagination.nextCursor) &&
          skipped < _maxSkippedPages;
      skipped++
    ) {
      page = await repo.list(cursor: page.pagination.nextCursor);
      kept = page.items.where((n) => !isChatMessage(n)).toList();
    }
    return CursorPage(items: kept, pagination: page.pagination);
  }

  StreamSubscription<NotificationReadEvent>? _readEvents;
  StreamSubscription<int>? _invalidations;
  bool _reconciling = false, _dirty = false;
  Future<void> _reconcile() async {
    _dirty = true;
    if (_reconciling) return;
    _reconciling = true;
    final session = PreferencesManager().sessionRevision;
    try {
      do {
        _dirty = false;
        await reconcileCachedPages();
        if (!isClosed && session == PreferencesManager().sessionRevision) {
          _applyRead();
        }
      } while (_dirty &&
          !isClosed &&
          session == PreferencesManager().sessionRevision);
    } finally {
      _reconciling = false;
    }
  }

  final _read = <String, DateTime>{};
  int _revision = PreferencesManager().sessionRevision;
  void _checkSession() {
    if (_revision != PreferencesManager().sessionRevision) {
      _revision = PreferencesManager().sessionRevision;
      _read.clear();
    }
  }

  void _applyRead() {
    if (isClosed) return;
    _checkSession();
    if (_read.isEmpty) return;
    emit(
      CursorListState(
        status: state.status,
        items: state.items.map(
          (item) => _read.containsKey(item['id'].toString())
              ? <String, dynamic>{
                  ...item,
                  'read_at':
                      item['read_at'] ??
                      _read[item['id'].toString()]!.toUtc().toIso8601String(),
                }
              : item,
        ),
        hasMore: state.hasMore,
        refreshing: state.refreshing,
        loadingMore: state.loadingMore,
        error: state.error,
        paginationError: state.paginationError,
      ),
    );
  }

  @override
  Future<void> load() async {
    await super.load();
    _applyRead();
  }

  @override
  Future<void> more({bool retry = false}) async {
    await super.more(retry: retry);
    _applyRead();
  }

  @override
  Future<void> close() async {
    await _readEvents?.cancel();
    await _invalidations?.cancel();
    await super.close();
  }
}
