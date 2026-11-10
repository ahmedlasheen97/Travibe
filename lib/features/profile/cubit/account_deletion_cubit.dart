import 'package:flutter/painting.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import '../data/account_repo.dart';

class AccountDeletionState {
  const AccountDeletionState({
    this.loading = false,
    this.deleted = false,
    this.error,
    this.sessionChanged = false,
  });
  final bool loading, deleted, sessionChanged;
  final AccountDeletionFailure? error;
}

class AccountDeletionCubit extends Cubit<AccountDeletionState> {
  AccountDeletionCubit({AccountRepo? repo})
    : _repo = repo ?? AccountRepo(),
      super(const AccountDeletionState()) {
    _preferences.addListener(_sessionChanged);
  }
  final AccountRepo _repo;
  final _preferences = PreferencesManager();
  int _generation = 0;
  bool _cleaning = false;
  void _sessionChanged() {
    if (_cleaning) return;
    ++_generation;
    emit(const AccountDeletionState(sessionChanged: true));
  }

  Future<void> submit(String password, {required bool confirmed}) async {
    if (isClosed ||
        state.loading ||
        state.deleted ||
        state.error?.outcomeUncertain == true ||
        state.sessionChanged) {
      return;
    }
    if (!confirmed || password.isEmpty) {
      emit(
        AccountDeletionState(
          error: AccountDeletionFailure(
            message: !confirmed
                ? 'Confirm permanent account deletion before continuing.'
                : 'Enter your current password.',
            statusCode: 422,
          ),
        ),
      );
      return;
    }
    if (!_preferences.hasSession) {
      emit(
        AccountDeletionState(
          error: AccountDeletionFailure(
            message: 'Sign in before deleting your account.',
            statusCode: 401,
          ),
        ),
      );
      return;
    }
    final generation = ++_generation;
    final session = _preferences.sessionRevision;
    emit(const AccountDeletionState(loading: true));
    bool current() =>
        !isClosed &&
        generation == _generation &&
        session == _preferences.sessionRevision;
    try {
      await _repo.delete(password);
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
        emit(const AccountDeletionState(deleted: true));
      }
    } catch (error) {
      if (!current()) return;
      emit(
        AccountDeletionState(
          error: error is AccountDeletionFailure
              ? error
              : AccountDeletionFailure.uncertain(),
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
