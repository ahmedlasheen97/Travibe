import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';
import 'package:travibe/features/profile/data/profile_model.dart';

class EmailChangeState {
  const EmailChangeState({
    this.sending = false,
    this.codeSentTo,
    this.passwordError,
    this.emailError,
    this.error,
  });

  final bool sending;

  /// Set once `POST /email/change` accepted the request.
  final String? codeSentTo;

  /// 422 on `current_password` (shown in the password dialog).
  final String? passwordError;

  /// 422 on `email` (shown under the New email field).
  final String? emailError;

  /// Any other failure.
  final String? error;
}

/// `POST /email/change` → OTP → `POST /email/change/verify`. The password is
/// kept in memory only for Resend (the API has no resend endpoint for this
/// flow) and dropped on close or session change.
class EmailChangeCubit extends Cubit<EmailChangeState> {
  EmailChangeCubit({AuthRepo? repo})
    : _repo = repo ?? AuthRepo(),
      super(const EmailChangeState()) {
    _session = _preferences.sessionRevision;
    _preferences.addListener(_sessionChanged);
  }

  final AuthRepo _repo;
  final _preferences = PreferencesManager();
  late int _session;
  String? _password;
  String? _email;

  bool get _current => !isClosed && _session == _preferences.sessionRevision;

  void _sessionChanged() {
    if (_session == _preferences.sessionRevision) return;
    _password = null;
    _email = null;
    if (!isClosed) {
      emit(
        const EmailChangeState(
          error: 'Your session changed. Reopen Settings to continue.',
        ),
      );
    }
  }

  /// Clears field errors once the user edits the email again.
  void clearEmailError() {
    if (state.emailError != null) emit(const EmailChangeState());
  }

  Future<void> request({
    required String password,
    required String email,
  }) async {
    if (!_current || state.sending) return;
    emit(const EmailChangeState(sending: true));
    try {
      await _repo.requestEmailChange(currentPassword: password, email: email);
      if (!_current) return;
      _password = password;
      _email = email;
      emit(EmailChangeState(codeSentTo: email));
    } catch (error) {
      if (!_current) return;
      final api = error is ApiError ? error : null;
      String? field(String key) => api?.fieldErrors[key]?.firstOrNull;
      final password = field('current_password') ?? field('password');
      final email = field('email');
      emit(
        EmailChangeState(
          passwordError: password,
          emailError: email,
          error: password == null && email == null
              ? api?.message ?? 'Unable to send the code. Please retry.'
              : null,
        ),
      );
    }
  }

  /// Sends a fresh code to the same address (re-posts the change request).
  Future<void> resend() async {
    final password = _password, email = _email;
    if (password == null || email == null || !_current) {
      throw ApiError(message: 'Reopen Email Address to request a new code.');
    }
    await _repo.requestEmailChange(currentPassword: password, email: email);
  }

  /// Throws [ApiError] on a wrong code; returns the updated user otherwise.
  Future<ProfileModel> verify(String code) async {
    final email = _email;
    final session = _session;
    if (email == null || !_current) {
      throw ApiError(message: 'Reopen Email Address to continue.');
    }
    final profile = await _repo.verifyEmailChange(email: email, code: code);
    if (isClosed || session != _preferences.sessionRevision) {
      throw ApiError(message: 'Your session changed. Reopen Settings.');
    }
    _password = null;
    return profile;
  }

  @override
  Future<void> close() {
    _password = null;
    _preferences.removeListener(_sessionChanged);
    return super.close();
  }
}
