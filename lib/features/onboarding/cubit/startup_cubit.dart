import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';
import 'package:travibe/features/profile/data/profile_model.dart';

enum StartupTarget { onboarding, home, login, verification, profileSetup }

class StartupDecision {
  const StartupDecision(this.target, {this.email, this.offline = false});
  final StartupTarget target;
  final String? email;

  /// Home was entered with a previously confirmed session that could not be
  /// re-validated (network only). The session still needs a background check.
  final bool offline;
}

class StartupState {
  const StartupState({
    this.decision,
    this.error,
    this.sessionRevision,
    this.loading = false,
  });
  final StartupDecision? decision;
  final String? error;
  final int? sessionRevision;
  final bool loading;
}

/// The request outcome is unknown or never reached the server.
bool isStartupNetworkError(Object error) =>
    error is TimeoutException ||
    error is SocketException ||
    (error is ApiError && (error.isConnectionError || error.isTimeout));

/// Reads the existing, already initialized PreferencesManager. Nothing treats a
/// token as proof of identity; only the canonical authenticated resource does.
class StartupCubit extends Cubit<StartupState> {
  StartupCubit({
    AuthRepo? auth,
    this.retryDelays = const [
      Duration(milliseconds: 400),
      Duration(milliseconds: 1200),
    ],
    this.attemptTimeout = const Duration(seconds: 8),
  }) : _auth = auth ?? AuthRepo(),
       super(const StartupState()) {
    _preferences.addListener(resolve);
  }

  /// Account-scoped: removed by `clearSession()` on logout/401.
  static const confirmedHomeKey = 'startup_confirmed_home';
  static const errorMessage =
      'Unable to verify your session. Check your connection and retry.';

  /// Delays between attempts; `retryDelays.length + 1` attempts in total.
  final List<Duration> retryDelays;
  final Duration attemptTimeout;
  final AuthRepo _auth;
  final _preferences = PreferencesManager();
  int _generation = 0;

  /// Network/timeouts, 5xx and status-less API failures may be transient;
  /// 4xx answers are definitive.
  static bool _retryable(Object error) =>
      isStartupNetworkError(error) ||
      (error is ApiError &&
          (error.statusCode == null || error.statusCode! >= 500));

  Future<void> resolve() async {
    if (isClosed) return;
    final generation = ++_generation;
    final session = _preferences.sessionRevision;
    bool current() =>
        !isClosed &&
        generation == _generation &&
        session == _preferences.sessionRevision;
    void finish(StartupTarget target, {String? email, bool offline = false}) {
      if (current()) {
        emit(
          StartupState(
            decision: StartupDecision(target, email: email, offline: offline),
            sessionRevision: session,
          ),
        );
      }
    }

    // Keep a visible error (with a spinner) while retrying from it.
    emit(StartupState(loading: true, error: state.error));
    if (!_preferences.onboardingCompleted) {
      finish(StartupTarget.onboarding);
      return;
    }
    if (!_preferences.hasSession) {
      finish(StartupTarget.login);
      return;
    }
    try {
      final user = await _currentUser(current);
      if (user == null || !current()) return;
      if (user.emailVerifiedAt?.isNotEmpty != true) {
        await _preferences.remove(confirmedHomeKey);
        if (!current()) return;
        if (user.email?.isNotEmpty == true) {
          finish(StartupTarget.verification, email: user.email);
        } else {
          finish(StartupTarget.login);
        }
        return;
      }
      // A backend-confirmed account locale may replace the app language. This
      // method checks sessionRevision again before beginning synchronous writes.
      if (const {'en', 'ar'}.contains(user.locale)) {
        await _preferences.saveUserPresentation(
          locale: user.locale!,
          currency: user.currencyCode,
          expectedSession: session,
        );
      }
      if (!current()) return;
      final home = user.profileCompleted == true;
      if (home) {
        await _preferences.setBool(confirmedHomeKey, true);
      } else {
        await _preferences.remove(confirmedHomeKey);
      }
      if (!current()) return;
      finish(home ? StartupTarget.home : StartupTarget.profileSetup);
    } catch (error) {
      if (!current()) return;
      if (error is ApiError && error.statusCode == 401) {
        // Only an explicit rejection invalidates local credentials. Its session
        // notification triggers a fresh decision; stale 401s never clear a login.
        await _preferences.clearSession();
      } else if (error is ApiError && error.statusCode == 403) {
        // /user requires a verified email/full-access token. Login can resume
        // the existing OTP flow. Forbidden is not proof of token revocation.
        finish(StartupTarget.login);
      } else if (isStartupNetworkError(error) &&
          _preferences.hasSession &&
          _preferences.getBool(confirmedHomeKey) == true) {
        // Don't block a previously confirmed account on connectivity; Home's
        // offline UI takes over and Root re-validates in the background.
        finish(StartupTarget.home, offline: true);
      } else {
        emit(const StartupState(error: errorMessage));
      }
    }
  }

  /// Retries transient failures with backoff. Returns null when superseded.
  Future<ProfileModel?> _currentUser(bool Function() current) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await _auth.currentUser(timeout: attemptTimeout);
      } catch (error) {
        if (!current()) return null;
        if (attempt >= retryDelays.length || !_retryable(error)) rethrow;
      }
      await Future<void>.delayed(retryDelays[attempt]);
      if (!current()) return null;
    }
  }

  @override
  Future<void> close() {
    ++_generation;
    _preferences.removeListener(resolve);
    return super.close();
  }
}
