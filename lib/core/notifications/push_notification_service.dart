import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/notifications/data/push_token_repository.dart';

import 'firebase_messaging_client.dart';
import 'push_message.dart';

enum PushTokenStatus { unavailable, idle, waitingForApns, ready, failed }

enum PushBackendStatus { unsupported, idle, pending, registered, failed }

/// Device transport + session-scoped ownership. Never decides auth routes or
/// trusts a push payload as authorization, a recipient ID, or a navigation URI.
class PushNotificationService extends ChangeNotifier {
  PushNotificationService({
    required this.client,
    PushTokenRepository repository = const UnavailablePushTokenRepository(),
    PreferencesManager? preferences,
    this.retryDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 16),
    ],
  }) : _repository = repository,
       _preferences = preferences ?? PreferencesManager() {
    _revision = _preferences.sessionRevision;
    _initialRevision = _revision;
    _backend = repository.supported
        ? PushBackendStatus.idle
        : PushBackendStatus.unsupported;
    _preferences.addListener(_sessionChanged);
  }

  final MessagingClient client;
  final PushTokenRepository _repository;
  final PreferencesManager _preferences;
  final List<Duration> retryDelays;
  final _activities = StreamController<PushActivity>.broadcast();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final Set<String> _seen = <String>{};
  final Set<String> _retiredTokens = <String>{};
  late int _revision, _initialRevision;
  int _generation = 0, _retryIndex = 0;
  bool _closed = false, _ready = false, _enabled = true, _rotate = false;
  bool _rotating = false, _requesting = false;
  PushPermission _permission = PushPermission.unknown;
  PushTokenStatus _tokenStatus = PushTokenStatus.unavailable;
  late PushBackendStatus _backend;
  String? _error, _token;
  PushAccount? _account;
  PushRegistration? _registration;
  PushDeviceRecord? _record;
  int? _pendingOpenRevision;
  void Function()? _openInbox;
  Future<void>? _startJob, _permissionJob, _tokenJob;
  int? _tokenJobGeneration;
  Future<void> _sdkTail = Future.value(), _backendTail = Future.value();
  Timer? _retry;

  PushPermission get permission => _permission;
  PushTokenStatus get tokenStatus => _tokenStatus;
  PushBackendStatus get backendStatus => _backend;
  bool get supported => _ready;
  bool get requestingPermission => _requesting;
  String? get error => _error;
  Stream<PushActivity> get activities => _activities.stream;
  bool get _allowed =>
      _enabled &&
      (_permission == PushPermission.authorized ||
          _permission == PushPermission.provisional);
  static const _timeout = Duration(seconds: 10);

  bool _current(int generation) =>
      !_closed &&
      generation == _generation &&
      _revision == _preferences.sessionRevision &&
      _preferences.hasSession &&
      _account?.sessionRevision == _revision;
  void _publish() {
    if (!_closed) notifyListeners();
  }

  void _fail(String message) {
    _error = message;
    _publish();
  }

  Future<void> start() => _startJob ??= _start();
  Future<void> _start() async {
    try {
      if (!await client.initialize().timeout(_timeout) || _closed) return;
      _ready = true;
      _tokenStatus = PushTokenStatus.idle;
      if (_rotate) unawaited(_rotateWithoutOwner());
      _subscriptions.addAll([
        client.tokenRefresh.listen(
          _refreshedToken,
          onError: (Object _) => _fail('Unable to refresh notifications.'),
        ),
        client.foreground.listen(
          (m) => _message(m, PushActivityKind.foreground),
          onError: (Object _) => _fail('Unable to receive notifications.'),
        ),
        client.opened.listen(
          (m) => _message(m, PushActivityKind.opened),
          onError: (Object _) => _fail('Unable to open notifications.'),
        ),
      ]);
      await refreshPermission();
      if (_closed) return;
      try {
        final initial = await client.initialMessage().timeout(_timeout);
        if (!_closed &&
            _initialRevision == _preferences.sessionRevision &&
            initial != null) {
          _message(initial, PushActivityKind.initial);
        }
      } catch (_) {
        _fail('Unable to read the initial notification.');
      }
    } catch (_) {
      _fail('Notifications are currently unavailable.');
    }
    _publish();
  }

  /// Called only by the existing authenticated CurrentUserCubit consumer.
  Future<void> updateAccount(
    String? userId, {
    required int expectedSession,
    bool deliveryEnabled = true,
  }) async {
    if (_closed || expectedSession != _preferences.sessionRevision) return;
    final parsedId = BigInt.tryParse(userId?.trim() ?? '');
    final id = parsedId != null && parsedId > BigInt.zero
        ? parsedId.toString()
        : null;
    if (!_preferences.hasSession || id == null) {
      if (_account != null) _reset(null, enabled: deliveryEnabled);
      return;
    }
    final generation = _generation;
    final token = await _preferences.getToken();
    if (_closed ||
        generation != _generation ||
        expectedSession != _preferences.sessionRevision ||
        token == null ||
        token.isEmpty) {
      return;
    }
    final next = PushAccount(
      userId: id,
      sessionRevision: expectedSession,
      authorizationToken: token,
    );
    if (_account == next && _enabled == deliveryEnabled) return;
    _reset(next, enabled: deliveryEnabled);
    unawaited(
      start().then((_) {
        if (_account == next && !_allowed) _cleanupAccount(next);
        return refreshToken();
      }),
    );
    _flushOpen();
  }

  void _sessionChanged() {
    if (_closed || _revision == _preferences.sessionRevision) return;
    _revision = _preferences.sessionRevision;
    _pendingOpenRevision = null;
    _rotate = true;
    _reset(null, enabled: true);
    if (_ready) unawaited(_rotateWithoutOwner());
  }

  void _reset(PushAccount? account, {required bool enabled}) {
    final previous = _account;
    ++_generation;
    _retry?.cancel();
    _retry = null;
    _retryIndex = 0;
    if (_record case final record?) _unregister(record);
    if (previous != null) _cleanupAccount(previous);
    if (_token case final token?) _remember(_retiredTokens, token);
    if (previous != null) {
      _pendingOpenRevision = null;
      _rotate = true;
    }
    _registration = null;
    _record = null;
    _token = null;
    _account = account;
    _enabled = enabled;
    if (account == null || previous != null && previous != account) {
      _seen.clear();
    }
    _error = null;
    _tokenStatus = _ready ? PushTokenStatus.idle : PushTokenStatus.unavailable;
    _backend = _repository.supported
        ? PushBackendStatus.idle
        : PushBackendStatus.unsupported;
    _publish();
  }

  Future<void> _sdk(Future<void> Function() work) {
    final job = _sdkTail.then((_) => work());
    _sdkTail = job.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return job;
  }

  Future<void> _rotateWithoutOwner() => _sdk(() async {
    if (_closed || !_rotate || !_ready) return;
    final generation = _generation;
    _rotating = true;
    try {
      await client.deleteToken().timeout(_timeout);
      if (generation == _generation) _rotate = false;
    } catch (_) {
      if (generation == _generation) {
        _fail('Unable to reset notification registration.');
      }
    } finally {
      _rotating = false;
    }
  });

  Future<void> refreshPermission() async {
    if (!_ready || _closed || _requesting) return;
    try {
      final permission = await client.permission().timeout(_timeout);
      if (_closed || _requesting) return;
      _permission = permission;
      _error = null;
      _retryIndex = 0;
      if (!_allowed) {
        if (_registration != null || _token != null) {
          _reset(_account, enabled: _enabled);
          unawaited(_rotateWithoutOwner());
        } else if (_account case final account?) {
          _cleanupAccount(account);
        }
      } else {
        unawaited(refreshToken());
      }
      _publish();
    } catch (_) {
      _fail('Unable to check notification permission.');
    }
  }

  Future<void> requestPermission() {
    if (_permissionJob != null) return _permissionJob!;
    final job = _requestPermission();
    _permissionJob = job;
    return job.whenComplete(() {
      if (identical(_permissionJob, job)) _permissionJob = null;
    });
  }

  Future<void> _requestPermission() async {
    _requesting = true;
    _publish();
    try {
      await start();
      if (!_ready || _closed) return;
      final permission = await client.requestPermission();
      if (_closed) return;
      _permission = permission;
      _error = null;
      _retryIndex = 0;
      if (_allowed) {
        await refreshToken();
      } else if (_token != null || _registration != null) {
        _reset(_account, enabled: _enabled);
        await _rotateWithoutOwner();
      }
    } catch (_) {
      _fail('Unable to request notification permission.');
    } finally {
      _requesting = false;
      _publish();
    }
  }

  Future<void> refreshToken() {
    final generation = _generation;
    if (!_ready || !_allowed || !_current(generation)) return Future.value();
    if (_tokenJob != null && _tokenJobGeneration == generation) {
      return _tokenJob!;
    }
    final job = _sdk(() => _readToken(generation));
    _tokenJob = job;
    _tokenJobGeneration = generation;
    return job.whenComplete(() {
      if (identical(_tokenJob, job)) _tokenJob = null;
    });
  }

  Future<void> _readToken(int generation) async {
    if (!_current(generation) || !_allowed) return;
    try {
      if (_rotate) {
        _rotating = true;
        try {
          await client.deleteToken().timeout(_timeout);
          if (generation == _generation) _rotate = false;
        } finally {
          _rotating = false;
        }
        if (!_current(generation)) return;
      }
      if (!await _apnsReady(generation)) return;
      final token = await client.token().timeout(_timeout);
      if (_current(generation)) _acceptToken(token, generation);
    } catch (_) {
      if (_current(generation)) {
        _tokenStatus = PushTokenStatus.failed;
        _fail('Unable to retrieve the notification token.');
      }
    }
  }

  Future<bool> _apnsReady(int generation) async {
    if (client.requiresApns) {
      final apns = await client.apnsToken().timeout(_timeout);
      if (!_current(generation)) return false;
      if (apns == null || apns.isEmpty) {
        _tokenStatus = PushTokenStatus.waitingForApns;
        _publish();
        _scheduleRetry(generation);
        return false;
      }
    }
    return _current(generation);
  }

  void _scheduleRetry(int generation) {
    if (_retry != null || _retryIndex >= retryDelays.length) return;
    _retry = Timer(retryDelays[_retryIndex++], () {
      _retry = null;
      if (_current(generation)) unawaited(refreshToken());
    });
  }

  void _refreshedToken(String token) {
    final generation = _generation;
    if (_rotating || !_current(generation) || !_allowed) return;
    // A queued stream event has no session stamp. Read the SDK's current token
    // after rotation instead of associating an old event value with a new user.
    unawaited(refreshToken());
  }

  void _acceptToken(String? token, int generation) {
    if (!_current(generation) || !_allowed) return;
    if (token == null ||
        token.trim().isEmpty ||
        token != token.trim() ||
        _retiredTokens.contains(token)) {
      _tokenStatus = PushTokenStatus.failed;
      _fail('A new notification token is not available yet.');
      return;
    }
    _token = token;
    _tokenStatus = PushTokenStatus.ready;
    _error = null;
    if (!_repository.supported) {
      _publish();
      return;
    }
    if (_registration?.token == token &&
        _registration?.account == _account &&
        _backend != PushBackendStatus.failed) {
      _publish();
      return;
    }
    final registration = PushRegistration(
      account: _account!,
      token: token,
      platform: client.platform,
    );
    _registration = registration;
    _backend = PushBackendStatus.pending;
    _publish();
    _backendTail = _backendTail.then((_) async {
      if (!_current(generation) || !identical(_registration, registration)) {
        return;
      }
      try {
        // A Future timeout does not cancel a server mutation. Keep this queue
        // ordered through actual completion so late registration cannot undo
        // logout revocation. An HTTP adapter must bound/cancel its own transport.
        final record = await _repository.register(registration);
        if (_current(generation) && identical(_registration, registration)) {
          _record = record;
          _backend = PushBackendStatus.registered;
          _publish();
          // Preserve the previous valid record until registration is confirmed.
          // Only this captured principal can clean its superseded device IDs.
          await _cleanupNow(registration.account, exceptId: record.id);
        } else if (!_closed ||
            _account != registration.account ||
            _revision != registration.account.sessionRevision) {
          // Logout/switch may precede the POST response containing its ID.
          // Finish stale cleanup before allowing the next queued registration.
          try {
            await _repository.unregister(record);
          } catch (_) {
            // Non-secret metadata remains for the same user's next session.
          }
        }
      } catch (_) {
        if (_current(generation) && identical(_registration, registration)) {
          _backend = PushBackendStatus.failed;
          _fail('Unable to register notifications. Please retry.');
        }
      }
    });
  }

  void _unregister(PushDeviceRecord record) {
    if (!_repository.supported) return;
    _backendTail = _backendTail.then((_) async {
      try {
        await _repository.unregister(record);
      } catch (_) {
        if (_account == record.registration.account) {
          _fail('Unable to revoke the previous notification registration.');
        }
      }
    });
  }

  void _cleanupAccount(PushAccount account) {
    if (!_repository.supported) return;
    _backendTail = _backendTail.then((_) => _cleanupNow(account));
  }

  Future<void> _cleanupNow(PushAccount account, {String? exceptId}) async {
    try {
      await _repository.cleanup(account, exceptId: exceptId);
    } catch (_) {
      if (_account == account) {
        _fail(
          'Unable to remove an earlier notification registration. Please retry.',
        );
      }
    }
  }

  void _message(PushMessage message, PushActivityKind kind) {
    if (_closed || !_preferences.hasSession) return;
    final opened = kind != PushActivityKind.foreground;
    if (!opened && (!_allowed || !_current(_generation))) return;
    final key = '${opened ? 'open' : 'receive'}:${message.key}';
    if (!_seen.add(key)) return;
    while (_seen.length > 128) {
      _seen.remove(_seen.first);
    }
    // Only an activity hint leaves this service. Without a verified recipient
    // schema no payload text, user ID, URI or post ID is exposed to UI/navigation.
    _activities.add(PushActivity(kind, _revision));
    if (opened) {
      _pendingOpenRevision = _revision;
      _flushOpen();
    }
  }

  void setNavigationHandler(void Function()? handler) {
    _openInbox = handler;
    _flushOpen();
  }

  void _flushOpen() {
    if (!_current(_generation) ||
        _openInbox == null ||
        _pendingOpenRevision != _preferences.sessionRevision) {
      return;
    }
    _pendingOpenRevision = null;
    _openInbox!();
  }

  static void _remember(Set<String> set, String value) {
    set.add(value);
    while (set.length > 128) {
      set.remove(set.first);
    }
  }

  Future<void> resume() async {
    _retryIndex = 0;
    await refreshPermission();
  }

  Future<void> retry() async {
    _retryIndex = 0;
    await refreshPermission();
    await refreshToken();
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    ++_generation;
    _preferences.removeListener(_sessionChanged);
    _retry?.cancel();
    _openInbox = null;
    _pendingOpenRevision = null;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_activities.close());
    // App shutdown is not logout: keep a valid server registration for pushes
    // while terminated. Session changes perform explicit revocation/rotation.
    super.dispose();
  }
}
