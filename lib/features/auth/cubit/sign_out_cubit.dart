import 'package:flutter/painting.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';

class SignOutState {
  const SignOutState({
    this.loading = false,
    this.signedOut = false,
    this.revoked = false,
    this.sessionChanged = false,
    this.error,
  });
  final bool loading, signedOut, revoked, sessionChanged;
  final String? error;
}

class SignOutCubit extends Cubit<SignOutState> {
  SignOutCubit({AuthRepo? repo})
    : _repo = repo ?? AuthRepo(),
      super(const SignOutState()) {
    _preferences.addListener(_sessionChanged);
  }
  final AuthRepo _repo;
  final _preferences = PreferencesManager();
  int _generation = 0;
  bool _cleaning = false;
  void _sessionChanged() {
    if (_cleaning || isClosed) return;
    ++_generation;
    emit(const SignOutState(sessionChanged: true));
  }

  Future<void> submit() async {
    if (isClosed || state.loading || state.signedOut || state.sessionChanged) {
      return;
    }
    final generation = ++_generation;
    final session = _preferences.sessionRevision;
    bool current() =>
        !isClosed &&
        generation == _generation &&
        session == _preferences.sessionRevision;
    emit(const SignOutState(loading: true));
    try {
      final revoked = _preferences.hasSession ? await _repo.logout() : false;
      if (!current()) return;
      _cleaning = true;
      try {
        await _preferences.clearSession();
        PaintingBinding.instance.imageCache
          ..clear()
          ..clearLiveImages();
      } finally {
        _cleaning = false;
      }
      if (!isClosed && generation == _generation && !_preferences.hasSession) {
        emit(SignOutState(signedOut: true, revoked: revoked));
      }
    } catch (_) {
      if (!current()) return;
      // No raw transport error may disclose tokens or claim uncertain revocation.
      emit(
        const SignOutState(
          error:
              'Log out could not be confirmed. You are still signed in on this device. Check your connection and try again.',
        ),
      );
    }
  }

  @override
  Future<void> close() {
    ++_generation;
    _preferences.removeListener(_sessionChanged);
    return super.close();
  }
}
