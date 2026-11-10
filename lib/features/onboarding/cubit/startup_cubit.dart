import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';

enum StartupTarget { onboarding, home, login, verification, profileSetup }

class StartupDecision {
  const StartupDecision(this.target, {this.email});
  final StartupTarget target;
  final String? email;
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

/// Reads the existing, already initialized PreferencesManager. Nothing treats a
/// token as proof of identity; only the canonical authenticated resource does.
class StartupCubit extends Cubit<StartupState> {
  StartupCubit({AuthRepo? auth})
    : _auth = auth ?? AuthRepo(),
      super(const StartupState()) {
    _preferences.addListener(resolve);
  }
  final AuthRepo _auth;
  final _preferences = PreferencesManager();
  int _generation = 0;

  Future<void> resolve() async {
    if (isClosed) return;
    final generation = ++_generation;
    final session = _preferences.sessionRevision;
    bool current() =>
        !isClosed &&
        generation == _generation &&
        session == _preferences.sessionRevision;
    void finish(StartupTarget target, {String? email}) {
      if (current()) {
        emit(
          StartupState(
            decision: StartupDecision(target, email: email),
            sessionRevision: session,
          ),
        );
      }
    }

    emit(const StartupState(loading: true));
    if (!_preferences.onboardingCompleted) {
      finish(StartupTarget.onboarding);
      return;
    }
    if (!_preferences.hasSession) {
      finish(StartupTarget.login);
      return;
    }
    try {
      final user = await _auth.currentUser();
      if (!current()) return;
      if (user.emailVerifiedAt?.isNotEmpty != true) {
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
      finish(
        user.profileCompleted == true
            ? StartupTarget.home
            : StartupTarget.profileSetup,
      );
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
      } else {
        emit(
          const StartupState(
            error:
                'Unable to verify your session. Check your connection and retry.',
          ),
        );
      }
    }
  }

  @override
  Future<void> close() {
    ++_generation;
    _preferences.removeListener(resolve);
    return super.close();
  }
}
