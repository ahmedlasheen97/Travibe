import 'dart:async';
import 'package:flutter/services.dart';
import 'package:travibe/features/chats/data/chat_reachability.dart';

/// Non-widget version of the chat banner's reconnect signal: polls the native
/// `networkStatus` interface report and listens to [ChatReachability]. While
/// started (only while something has failed), [onReconnect] fires when the
/// interface goes offline → online or an API response proves connectivity,
/// and every third tick as a probe. Unknown/unsupported status never counts as
/// offline.
class ReconnectMonitor {
  ReconnectMonitor({
    Future<bool?> Function()? status,
    ChatReachability? reachability,
    this.interval = const Duration(seconds: 5),
  }) : _status = status ?? _platformStatus,
       _reachability = reachability ?? ChatReachability.instance;

  static const _channel = MethodChannel('travibe/chat_media');
  static const _trustReachable = Duration(seconds: 10);
  static const _probeEvery = 3;

  static Future<bool?> _platformStatus() =>
      _channel.invokeMethod<bool>('networkStatus');

  final Future<bool?> Function() _status;
  final ChatReachability _reachability;
  final Duration interval;

  Timer? _timer, _timeout;
  Completer<bool?>? _response;
  void Function()? _onReconnect;
  bool? _connected;
  bool _checking = false;
  int _offlineTicks = 0;

  bool get isRunning => _onReconnect != null;

  void start(void Function() onReconnect) {
    final wasRunning = isRunning;
    _onReconnect = onReconnect;
    if (wasRunning) return;
    _connected = null;
    _offlineTicks = 0;
    _reachability.addListener(_reachable);
    _timer = Timer.periodic(interval, (_) => unawaited(_check()));
    unawaited(_check());
  }

  void stop() {
    if (!isRunning) return;
    _onReconnect = null;
    _timer?.cancel();
    _timer = null;
    _timeout?.cancel();
    final response = _response;
    if (response != null && !response.isCompleted) response.complete(null);
    _reachability.removeListener(_reachable);
  }

  void _reachable() {
    if (!isRunning) return;
    _connected = true;
    _onReconnect?.call();
  }

  Future<void> _check() async {
    if (_checking || !isRunning) return;
    _checking = true;
    try {
      final response = Completer<bool?>();
      _response = response;
      _timeout = Timer(const Duration(seconds: 3), () {
        if (!response.isCompleted) response.complete(null);
      });
      Future<bool?>.sync(_status).then(
        (value) {
          if (!response.isCompleted) response.complete(value);
        },
        onError: (Object _) {
          if (!response.isCompleted) response.complete(null);
        },
      );
      var value = await response.future;
      if (!isRunning) return;
      // A recent API response outranks a stale interface report.
      if (value == false && _reachability.reachedWithin(_trustReachable)) {
        value = true;
      }
      final reconnect = _connected == false && value == true;
      if (value != null) _connected = value;
      if (reconnect) {
        _offlineTicks = 0;
        _onReconnect?.call();
      } else if (++_offlineTicks % _probeEvery == 0) {
        // Still failing (offline, unknown, or a server error while online):
        // periodically probe with a quiet retry.
        _onReconnect?.call();
      }
    } finally {
      _timeout?.cancel();
      _timeout = null;
      _response = null;
      _checking = false;
    }
  }

  void dispose() => stop();
}
