import 'dart:async';
import 'package:travibe/core/cubit/cursor_list_cubit.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/notifications/data/notifications_repo.dart';
import 'notification_activity.dart';

class NotificationsCubit extends CursorListCubit<Map<String, dynamic>> {
  NotificationsCubit({NotificationsRepo? repo, NotificationActivity? activity})
    : this._(repo ?? activity?.repository ?? NotificationsRepo(), activity);
  NotificationsCubit._(NotificationsRepo repo, NotificationActivity? activity)
    : super(
        loadPage: (cursor) => repo.list(cursor: cursor),
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
