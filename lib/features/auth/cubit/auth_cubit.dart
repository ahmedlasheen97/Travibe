import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/material.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';

import 'package:travibe/features/auth/data/google_auth_service.dart';
import 'package:travibe/features/auth/data/auth_response_model.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';

part 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  AuthCubit({AuthRepo? repo, GoogleAuthService? google})
    : authRepo = repo ?? AuthRepo(),
      google = google ?? GoogleAuthService(),
      super(AuthInitial());
  final AuthRepo authRepo;
  final GoogleAuthService google;

  Future<void> loginWithGoogle() async {
    if (isClosed || state is AuthLoading) return;
    final session = PreferencesManager();
    final revision = session.sessionRevision;
    bool active() => !isClosed && session.sessionRevision == revision;
    emit(AuthLoading());
    try {
      final idToken = await google.signIn();
      if (!active()) return;
      if (idToken == null) {
        emit(AuthInitial());
        return;
      }
      final response = await authRepo.googleLogin(idToken, canCommit: active);
      final currentToken = await session.getToken();
      if (!isClosed && currentToken == response.token) {
        emit(AuthSuccess(response: response));
      }
    } catch (error) {
      if (!active()) return;
      emit(
        AuthFailure(
          error is ApiError
              ? error.message
              : 'Unable to sign in with Google. Please retry.',
        ),
      );
    }
  }

  TextEditingController emailController = TextEditingController();
  TextEditingController passwordController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  static final _emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,}$');
  static final _passwordRegex = RegExp(r'^(?=.*[A-Za-z])(?=.*\d).{8,}$');

  String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your email';
    }
    if (!_emailRegex.hasMatch(value.trim())) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your password';
    }
    if (!_passwordRegex.hasMatch(value)) {
      return 'Password must be at least 8 characters and contain a letter and a number';
    }
    return null;
  }

  Future<void> login(String email, String password) async {
    if (isClosed || state is AuthLoading) return;
    emit(AuthLoading());
    try {
      final response = await authRepo.login(email, password);
      if (isClosed) return;
      // Keep the backend's verification requirement available to LoginScreen.
      emit(AuthSuccess(response: response));
    } catch (e) {
      String errorMessage = 'something went wrong';
      // If login fails, emit AuthFailure with an error message
      if (e is ApiError) {
        errorMessage = e.toString();
      }
      emit(AuthFailure(errorMessage));
    }
  }

  @override
  Future<void> close() {
    emailController.dispose();
    passwordController.dispose();
    return super.close();
  }
}
