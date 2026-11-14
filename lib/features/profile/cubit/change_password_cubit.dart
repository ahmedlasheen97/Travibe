import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';

enum PasswordField { current, password, confirmation }

class ChangePasswordState {
  const ChangePasswordState({
    this.submitting = false,
    this.done = false,
    this.fieldErrors = const {},
    this.error,
  });

  final bool submitting;

  /// `PATCH /password` succeeded.
  final bool done;

  /// 422 messages shown under the matching field.
  final Map<PasswordField, String> fieldErrors;

  /// Any other failure (shown as a toast).
  final String? error;
}

/// `PATCH /password`. Results from a previous session are dropped.
class ChangePasswordCubit extends Cubit<ChangePasswordState> {
  ChangePasswordCubit({AuthRepo? repo})
    : _repo = repo ?? AuthRepo(),
      super(const ChangePasswordState());

  final AuthRepo _repo;
  final _preferences = PreferencesManager();

  static const _keys = {
    'current_password': PasswordField.current,
    'password': PasswordField.password,
    'password_confirmation': PasswordField.confirmation,
  };

  Future<void> submit({
    required String currentPassword,
    required String password,
    required String passwordConfirmation,
  }) async {
    if (isClosed || state.submitting || state.done) return;
    final session = _preferences.sessionRevision;
    bool current() => !isClosed && session == _preferences.sessionRevision;
    emit(const ChangePasswordState(submitting: true));
    try {
      await _repo.changePassword(
        currentPassword: currentPassword,
        password: password,
        passwordConfirmation: passwordConfirmation,
      );
      if (!current()) return;
      emit(const ChangePasswordState(done: true));
    } catch (error) {
      if (!current()) return;
      final api = error is ApiError ? error : null;
      final fields = <PasswordField, String>{
        for (final MapEntry(:key, :value) in _keys.entries)
          value: ?api?.fieldErrors[key]?.firstOrNull,
      };
      emit(
        ChangePasswordState(
          fieldErrors: fields,
          error: fields.isEmpty
              ? api?.message ?? 'Unable to update your password. Please retry.'
              : null,
        ),
      );
    }
  }

  /// Clears [field]'s server error once the user edits it.
  void clearFieldError(PasswordField field) {
    if (!state.fieldErrors.containsKey(field) || state.submitting) return;
    emit(
      ChangePasswordState(
        fieldErrors: Map.of(state.fieldErrors)..remove(field),
      ),
    );
  }
}
