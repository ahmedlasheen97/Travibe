import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';

/// Native identity only. Laravel remains the application's session authority.
class GoogleAuthService {
  static const iosClientId =
      '260901900671-fg8qsqc60vaesd1p6m62pm0jemmddfih.apps.googleusercontent.com';
  static const webClientId =
      '260901900671-jp93den2ef4gp61m0l1clv646h1bc25l.apps.googleusercontent.com';
  static Future<void>? _initialization;

  /// Null means the user cancelled; it is not a failed Travibe login.
  Future<String?> signIn() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      throw ApiError(message: 'Google sign-in is currently available on iOS.');
    }
    final google = GoogleSignIn.instance;
    await (_initialization ??= google.initialize(
      clientId: iosClientId,
      serverClientId: webClientId,
    ));
    try {
      final account = await google.authenticate();
      final token = account.authentication.idToken;
      if (token == null || token.trim().isEmpty) {
        throw ApiError(
          message: 'Google did not return an ID token. Please retry.',
        );
      }
      return token;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) return null;
      // Native exception descriptions may contain credentials; do not log them.
      throw ApiError(message: 'Unable to sign in with Google. Please retry.');
    }
  }
}
