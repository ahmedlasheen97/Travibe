import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';
import 'package:travibe/features/onboarding/cubit/startup_cubit.dart';

/// Marker passed as GoRouter `extra` when startup entered Home offline.
class OfflineStartup {
  const OfflineStartup();
}

/// Confirms a session that startup let into Home without reaching `/user`.
/// Keeps retrying with backoff until the server answers. Only an explicit 401
/// clears credentials; 403 returns to login like startup does.
class SessionRevalidator {
  SessionRevalidator({
    AuthRepo? auth,
    this.backoff = const [
      Duration(seconds: 5),
      Duration(seconds: 10),
      Duration(seconds: 20),
      Duration(seconds: 40),
      Duration(seconds: 60),
    ],
  }) : _auth = auth ?? AuthRepo();
  final AuthRepo _auth;

  /// Delay before each retry; the last value repeats.
  final List<Duration> backoff;
  final _preferences = PreferencesManager();
  VoidCallback? _onSignedOut;
  Timer? _timer;
  int? _session;
  int _failures = 0;
  bool _inFlight = false;
  bool _done = false;

  bool get isDone => _done;

  void start({required VoidCallback onSignedOut}) {
    if (_session != null || _done) return;
    _onSignedOut = onSignedOut;
    _session = _preferences.sessionRevision;
    unawaited(_attempt());
  }

  /// Skip the remaining backoff, e.g. when the app returns to the foreground.
  void retryNow() {
    if (_session == null || _done || _inFlight) return;
    _timer?.cancel();
    unawaited(_attempt());
  }

  bool get _current =>
      !_done &&
      _session == _preferences.sessionRevision &&
      _preferences.hasSession;

  Future<void> _attempt() async {
    if (!_current) return dispose();
    _inFlight = true;
    try {
      await _auth.currentUser();
      if (_current) dispose();
    } catch (error) {
      if (!_current) return dispose();
      if (error is ApiError && error.statusCode == 401) {
        final signedOut = _onSignedOut;
        dispose();
        await _preferences.clearSession();
        signedOut?.call();
      } else if (error is ApiError && error.statusCode == 403) {
        final signedOut = _onSignedOut;
        dispose();
        signedOut?.call();
      } else {
        final delay = backoff[_failures.clamp(0, backoff.length - 1)];
        _failures++;
        if (!isStartupNetworkError(error) && _failures > backoff.length) {
          // A persistent non-network failure; stop polling.
          return dispose();
        }
        _timer = Timer(delay, () => unawaited(_attempt()));
      }
    } finally {
      _inFlight = false;
    }
  }

  void dispose() {
    _done = true;
    _timer?.cancel();
    _timer = null;
    _onSignedOut = null;
  }
}
