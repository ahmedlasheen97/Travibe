import 'dart:async';

/// Transport-independent invalidation only. Payload text/routes are never UI data.
class ChatRealtimeEvent {
  const ChatRealtimeEvent({required this.id, required this.sessionRevision});
  final String id;
  final int sessionRevision;
}

abstract interface class ChatRealtimeTransport {
  Stream<ChatRealtimeEvent> get events;
  Future<void> connect();
  Future<void> subscribe(String verifiedChannel);
  Future<void> unsubscribe(String verifiedChannel);
  Future<void> disconnect();
}

/// Production binding stays disabled until authenticated subscription and
/// delivery are verified; public deployment and event contracts are documented.
/// The owning route supplies captured revision and closes this on lifecycle exit.
class ChatRealtimeCoordinator {
  ChatRealtimeCoordinator({
    required this.transport,
    required this.sessionRevision,
    required this.onActivity,
  });
  final ChatRealtimeTransport transport;
  final int sessionRevision;
  final void Function() onActivity;
  StreamSubscription<ChatRealtimeEvent>? _subscription;
  final Set<String> _seen = {};
  int _generation = 0;
  bool _disposed = false;
  Future<void>? _starting;
  Future<void> start() => _starting ??= _start();
  Future<void> _start() async {
    if (_disposed) return;
    final generation = ++_generation;
    _subscription = transport.events.listen((event) {
      if (_disposed ||
          event.sessionRevision != sessionRevision ||
          !_seen.add(event.id)) {
        return;
      }
      if (_seen.length > 512) _seen.remove(_seen.first);
      onActivity();
    }, onError: (Object _) {});
    for (var attempt = 0; attempt < 4; attempt++) {
      if (_disposed || generation != _generation) return;
      try {
        await transport.connect();
        if (_disposed || generation != _generation) {
          await transport.disconnect();
        }
        return;
      } catch (_) {
        if (attempt < 3) {
          await Future<void>.delayed(
            Duration(milliseconds: 250 * (1 << attempt)),
          );
        }
      }
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    await _subscription?.cancel();
    _seen.clear();
    await transport.disconnect();
  }
}
