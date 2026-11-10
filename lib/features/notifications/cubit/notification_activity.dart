import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import '../data/notifications_repo.dart';

class NotificationReadEvent {
  const NotificationReadEvent(
    this.sessionRevision,
    this.ids,
    this.at, {
    this.reopened = false,
  });
  final int sessionRevision;
  final Set<String> ids;
  final DateTime at;
  final bool reopened;
}

/// App-scoped count/read synchronization, independent from FCM availability.
class NotificationActivity extends ChangeNotifier {
  NotificationActivity({NotificationsRepo? repo})
    : repository = repo ?? NotificationsRepo() {
    _revision = _session.sessionRevision;
    _session.addListener(_sessionChanged);
  }
  final NotificationsRepo repository;
  final _session = PreferencesManager();
  final _reads = StreamController<NotificationReadEvent>.broadcast();
  final _invalidations = StreamController<int>.broadcast();
  Stream<int> get invalidations => _invalidations.stream;
  void invalidateFromRealtime({
    String? reopenedId,
    Iterable<String> reopenedIds = const [],
  }) {
    if (_closed || !_session.hasSession) return;
    final ids = {?reopenedId, ...reopenedIds};
    if (ids.isNotEmpty) {
      for (final id in ids) {
        _reopened[id] = ++_reopenRevision;
      }
      _reads.add(
        NotificationReadEvent(_revision, ids, DateTime.now(), reopened: true),
      );
    }
    _invalidations.add(_session.sessionRevision);
    unawaited(refresh(invalidate: true));
  }

  late int _revision;
  int _generation = 0, _count = 0;
  bool _closed = false, _dirty = false;
  Future<void>? _pending;
  final Map<String, Future<bool>> _mutations = {};
  Set<String> _allPendingIds = {};
  final Map<String, int> _reopened = {};
  int _reopenRevision = 0;
  ApiError? error;
  int get count => _count;
  bool get loading => _pending != null;
  bool get markingAll => _mutations.containsKey('*');
  bool marking(String id) => markingAll || _mutations.containsKey(id);
  Stream<NotificationReadEvent> get reads => _reads.stream;
  void _publish() {
    if (!_closed) notifyListeners();
  }

  bool _current(int revision) =>
      !_closed && revision == _session.sessionRevision && _session.hasSession;
  void _sessionChanged() {
    if (_revision == _session.sessionRevision) return;
    _revision = _session.sessionRevision;
    ++_generation;
    _pending = null;
    _dirty = false;
    _count = 0;
    error = null;
    _mutations.clear();
    _allPendingIds = {};
    _reopened.clear();
    _publish();
  }

  Future<void> refresh({bool invalidate = false}) {
    if (_closed || !_session.hasSession) return Future.value();
    if (invalidate) {
      ++_generation;
      _dirty = true;
    }
    if (_pending != null) return _pending!;
    final revision = _revision;
    final job = _fetch(revision);
    _pending = job;
    _publish();
    return job.whenComplete(() {
      if (identical(job, _pending)) {
        _pending = null;
        _publish();
      }
    });
  }

  Future<void> _fetch(int revision) async {
    do {
      _dirty = false;
      final generation = _generation;
      try {
        final result = await repository.unreadCount();
        if (_current(revision) && generation == _generation) {
          _count = result.value;
          error = null;
          _publish();
        }
      } catch (e) {
        if (_current(revision) && generation == _generation) {
          error = e is ApiError
              ? e
              : ApiError(message: 'Unable to load notification count.');
          _publish();
        }
      }
    } while (_current(revision) && _dirty);
  }

  Future<bool> markRead(String id) => _mutate(id, {id});
  Future<bool> markAllRead({Iterable<String> ids = const []}) =>
      _mutate('*', Set.of(ids));
  Future<bool> _mutate(String key, Set<String> ids) {
    if (_closed || !_session.hasSession) return Future.value(false);
    if (_mutations[key] != null) return _mutations[key]!;
    if (markingAll) {
      final all = _mutations['*']!;
      final revision = _revision;
      if (key == '*' || _allPendingIds.contains(key)) return all;
      return all.then(
        (ok) =>
            ok && _current(revision) ? _mutate(key, ids) : Future.value(false),
      );
    }
    final revision = _revision;
    if (key == '*') _allPendingIds = Set.of(ids);
    final job = _write(key, revision, ids);
    _mutations[key] = job;
    _publish();
    return job.whenComplete(() {
      if (identical(_mutations[key], job)) {
        _mutations.remove(key);
        _publish();
      }
    });
  }

  Future<bool> _write(String key, int revision, Set<String> ids) async {
    final reopened = {for (final id in ids) id: _reopened[id]};
    final generation = _generation;
    try {
      if (key == '*') {
        await repository.markAllRead();
      } else {
        await repository.markRead(key);
      }
      if (!_current(revision)) return false;
      error = null;
      if (key == '*' && generation == _generation) {
        ++_generation;
        _count = 0;
        _publish();
      }
      _reads.add(
        NotificationReadEvent(
          revision,
          Set.unmodifiable(ids.where((id) => reopened[id] == _reopened[id])),
          DateTime.now(),
        ),
      );
      await refresh(invalidate: true);
      return _current(revision);
    } catch (e) {
      if (_current(revision)) {
        error = e is ApiError
            ? e
            : ApiError(
                message: 'Unable to mark notifications as read. Please retry.',
              );
        _publish();
      }
      return false;
    }
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    ++_generation;
    _session.removeListener(_sessionChanged);
    unawaited(_reads.close());
    unawaited(_invalidations.close());
    super.dispose();
  }
}
