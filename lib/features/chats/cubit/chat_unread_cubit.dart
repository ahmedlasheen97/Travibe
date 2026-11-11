import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import '../data/chat_repository.dart';

class ChatUnreadState {
  const ChatUnreadState({
    this.count = 0,
    this.loading = false,
    this.confirmed = false,
    this.error = false,
    this.session = 0,
  });
  bool get hasUnread => count > 0;
  final int count;
  final bool loading, confirmed, error;
  final int session;
}

/// Sum of documented per-viewer unread *message* counts over every Inbox and
/// Requests page. Never publish a partial sum or increment from socket payloads.
class ChatUnreadCubit extends Cubit<ChatUnreadState> {
  ChatUnreadCubit({
    ChatRepository? repository,
    this.maxPages = 100,
    this.reconcileInterval = const Duration(seconds: 45),
  }) : _repository = repository ?? LaravelChatRepository(),
       super(const ChatUnreadState()) {
    if (maxPages < 1) throw ArgumentError.value(maxPages, 'maxPages');
    _session = _preferences.sessionRevision;
    _preferences.addListener(_sessionChanged);
  }
  final ChatRepository _repository;
  final int maxPages;
  final Duration reconcileInterval;
  Timer? _poll;
  final _preferences = PreferencesManager();
  late int _session;
  Object? _owner;
  String? _account;
  bool _foreground = true, _dirty = false;
  int _generation = 0, _revision = 0;
  Future<void>? _pending;

  /// Per-conversation counts from the last confirmed scan.
  final Map<String, int> _counts = {};

  /// Conversations marked read locally, keyed by a logical clock. A scan that
  /// started before a read settled could still carry the old server count.
  final Map<String, int> _readAt = {};
  final Set<String> _readsInFlight = {};
  int _readClock = 0;
  bool get _eligible =>
      !isClosed &&
      _owner != null &&
      _account != null &&
      _foreground &&
      _preferences.hasSession;
  bool _current(int generation, int session) =>
      _eligible &&
      generation == _generation &&
      session == _preferences.sessionRevision;
  void attach(Object owner) {
    if (identical(_owner, owner)) return;
    _owner = owner;
    _polling();
    unawaited(refresh());
  }

  void detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _invalidate();
    _polling();
  }

  void account(String? id) {
    if (isClosed) return;
    id = id?.trim();
    if (id?.isEmpty == true) id = null;
    if (_account == id) return;
    _account = id;
    _invalidate();
    emit(ChatUnreadState(session: _preferences.sessionRevision));
    _polling();
    unawaited(refresh());
  }

  void _polling() {
    _poll?.cancel();
    _poll = null;
    if (_eligible && reconcileInterval > Duration.zero) {
      _poll = Timer.periodic(reconcileInterval, (_) {
        if (_pending == null) unawaited(refresh());
      });
    }
  }

  void _invalidate() {
    _counts.clear();
    _readAt.clear();
    _readsInFlight.clear();
    ++_generation;
    _revision++;
    _dirty = false;
    _pending = null;
    _repository.cancel();
  }

  void _sessionChanged() {
    if (_session == _preferences.sessionRevision) return;
    _session = _preferences.sessionRevision;
    _account = null;
    _invalidate();
    _polling();
    emit(ChatUnreadState(session: _session));
  }

  void foreground(bool value) {
    if (_foreground == value) return;
    _foreground = value;
    _polling();
    if (value) {
      unawaited(refresh());
    } else {
      _invalidate();
    }
  }

  /// Optimistically drops [id] from the total while [read] (the mark-read
  /// request) runs, then reconciles with the server. Scans that started before
  /// the read settled cannot restore the old count; a failed read rolls back
  /// through the follow-up refresh.
  Future<void> trackRead(String id, Future<void> read) async {
    if (isClosed || id.isEmpty) return;
    final session = _preferences.sessionRevision;
    final previous = _counts[id] ?? 0;
    _counts[id] = 0;
    _readAt[id] = ++_readClock;
    _readsInFlight.add(id);
    // Drop any in-flight scan result; it may predate the read.
    ++_revision;
    if (previous > 0) {
      emit(
        ChatUnreadState(
          count: (state.count - previous).clamp(0, state.count),
          confirmed: state.confirmed,
          session: state.session,
        ),
      );
    }
    var succeeded = false;
    try {
      await read;
      succeeded = true;
    } catch (_) {
      // Rolled back below by the server count.
    }
    if (isClosed || session != _preferences.sessionRevision) return;
    _readsInFlight.remove(id);
    if (succeeded) {
      _readAt[id] = ++_readClock;
    } else {
      _readAt.remove(id);
    }
    await refresh();
  }

  Future<void> refresh() {
    if (!_eligible) return Future.value();
    ++_revision;
    _dirty = true;
    if (_pending != null) return _pending!;
    final generation = _generation, session = _preferences.sessionRevision;
    final job = _refresh(generation, session);
    _pending = job;
    return job.whenComplete(() {
      if (identical(_pending, job)) _pending = null;
    });
  }

  Future<void> _refresh(int generation, int session) async {
    do {
      _dirty = false;
      final revision = _revision;
      emit(
        ChatUnreadState(
          count: state.count,
          confirmed: state.confirmed,
          loading: true,
          session: session,
        ),
      );
      try {
        final unread = await _scan(generation, session);
        if (_current(generation, session) && revision == _revision) {
          emit(
            ChatUnreadState(count: unread, confirmed: true, session: session),
          );
        }
      } catch (_) {
        if (_current(generation, session) && revision == _revision) {
          emit(
            ChatUnreadState(
              count: state.count,
              confirmed: state.confirmed,
              error: true,
              session: session,
            ),
          );
        }
      }
    } while (_current(generation, session) && _dirty);
  }

  Future<int> _scan(int generation, int session) async {
    final started = _readClock;
    final active = [true, _repository.capabilities.requests];
    final cursors = <String?>[null, null];
    final seen = [<String>{}, <String>{}];
    var pages = 0;
    final counts = <String, int>{};
    while (active.any((value) => value)) {
      // Interleave Inbox/Requests so a long read Inbox cannot starve requests.
      for (var index = 0; index < 2; index++) {
        if (!active[index]) continue;
        if (!_current(generation, session)) {
          throw StateError('Session changed.');
        }
        if (++pages > maxPages) throw StateError('Unread scan incomplete.');
        final page = await _repository.conversations(
          continuation: cursors[index],
          requests: index == 1,
        );
        if (!_current(generation, session)) {
          throw StateError('Session changed.');
        }
        for (final item in page.items) {
          if (!item.hasUnreadCount || item.unread < 0 || item.id.isEmpty) {
            throw StateError('Unread state unavailable.');
          }
          final previous = counts[item.id];
          if (previous != null && previous != item.unread) {
            // Moving between Inbox/Requests during a scan needs a fresh snapshot.
            throw StateError('Unread snapshot changed.');
          }
          counts[item.id] = item.unread;
        }
        final next = page.continuation;
        if (next != null && !seen[index].add(next)) {
          throw StateError('Invalid pagination.');
        }
        cursors[index] = next;
        active[index] = next != null;
      }
    }
    for (final id in counts.keys) {
      final readAt = _readAt[id];
      if (readAt != null && (_readsInFlight.contains(id) || readAt > started)) {
        counts[id] = 0;
      } else if (readAt != null) {
        _readAt.remove(id);
      }
    }
    _counts
      ..clear()
      ..addAll(counts);
    return counts.values.fold<int>(0, (sum, count) => sum + count);
  }

  @override
  Future<void> close() {
    _poll?.cancel();
    _preferences.removeListener(_sessionChanged);
    _invalidate();
    return super.close();
  }
}
