import 'dart:async';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';

/// No production implementation until heartbeat/typing bodies and intervals
/// are confirmed. None of these methods imply a guessed Laravel JSON schema.
abstract interface class ChatActivityRepository {
  Future<void> heartbeat();
  Future<void> leavePresence();
  Future<void> typing(String conversationId);
  void cancel();
}

/// Opt-in lifecycle driver. Host supplies confirmed intervals and explicitly
/// resumes/pauses it; no background timers or permission assumptions by default.
class ChatActivityController {
  ChatActivityController({
    required this.repository,
    required this.heartbeatInterval,
    required this.typingInterval,
  }) {
    if (heartbeatInterval <= Duration.zero || typingInterval <= Duration.zero) {
      throw ArgumentError('Activity intervals must be positive.');
    }
    _session = _preferences.sessionRevision;
    _preferences.addListener(pause);
  }
  final ChatActivityRepository repository;
  final Duration heartbeatInterval, typingInterval;
  final _preferences = PreferencesManager();
  late final int _session;
  Timer? _heartbeat, _typingCooldown;
  bool _active = false, _sendingHeartbeat = false, _disposed = false;
  bool get _current =>
      !_disposed &&
      _preferences.hasSession &&
      _session == _preferences.sessionRevision;
  void resume() {
    if (!_current || _active) return;
    _active = true;
    unawaited(_beat());
    _heartbeat = Timer.periodic(heartbeatInterval, (_) => unawaited(_beat()));
  }

  Future<void> _beat() async {
    if (!_current || !_active || _sendingHeartbeat) return;
    _sendingHeartbeat = true;
    try {
      await repository.heartbeat();
    } catch (_) {
      /* Retry on next scheduled heartbeat. */
    } finally {
      _sendingHeartbeat = false;
    }
  }

  void typing(String conversationId) {
    if (!_current ||
        !_active ||
        _typingCooldown != null ||
        conversationId.isEmpty) {
      return;
    }
    _typingCooldown = Timer(typingInterval, () => _typingCooldown = null);
    unawaited(_typing(conversationId));
  }

  Future<void> _typing(String id) async {
    try {
      await repository.typing(id);
    } catch (_) {
      /* Typing is optional. */
    }
  }

  void pause() {
    _active = false;
    _heartbeat?.cancel();
    _heartbeat = null;
    _typingCooldown?.cancel();
    _typingCooldown = null;
    repository.cancel();
    // Do not send an old account's DELETE with replacement credentials.
    // A verified implementation may perform captured-principal cleanup itself.
  }

  Future<void> dispose() async {
    if (_disposed) return;
    final canLeave = _current && _active;
    _preferences.removeListener(pause);
    pause();
    _disposed = true;
    if (canLeave) {
      try {
        await repository.leavePresence();
      } catch (_) {}
    }
  }
}
