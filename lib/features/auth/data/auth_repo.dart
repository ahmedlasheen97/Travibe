import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_exceptions.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/auth/data/auth_response_model.dart';
import 'package:travibe/features/profile/data/profile_model.dart';

class AuthRepo {
  AuthRepo({ApiService? apiService}) : _apiService = apiService ?? ApiService();
  final ApiService _apiService;

  Future<bool> logout() => _apiService.revokeCurrentToken();

  /// A persisted bearer token is only a candidate session. The existing /user
  /// resource confirms identity, verification and profile setup at startup.
  Future<ProfileModel> currentUser({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final response = await _apiService.get('user').timeout(timeout);
    final data = response is Map ? response['data'] : null;
    if (data is! Map<String, dynamic> ||
        !data.containsKey('email_verified_at') ||
        data['profile_completed'] is! bool ||
        data['email'] is! String ||
        (data['email'] as String).isEmpty) {
      throw ApiError(message: 'Unable to verify your account. Please retry.');
    }
    return ProfileModel.fromJson(data);
  }

  Future<AuthResponseModel> googleLogin(
    String idToken, {
    required bool Function() canCommit,
  }) async {
    if (idToken.trim().isEmpty) {
      throw ApiError(
        message: 'Google did not return an ID token. Please retry.',
      );
    }
    final response = await _apiService.post('auth/google/token', {
      'device_name': 'iPhone',
      'id_token': idToken,
      'nonce': null,
      'name': null,
    });
    try {
      if (response is! Map<String, dynamic>) throw const FormatException();
      final data = response['data'];
      if (data is! Map<String, dynamic> ||
          data['token'] is! String ||
          (data['token'] as String).trim().isEmpty ||
          data['token_type'] != 'Bearer' ||
          data['user'] is! Map<String, dynamic> ||
          ![
            true,
            false,
            'true',
            'false',
            1,
            0,
            '1',
            '0',
          ].contains(data['email_verification_required'])) {
        throw const FormatException();
      }
      final result = AuthResponseModel.fromJson(response);
      if (result.emailVerificationRequired && result.user.email.isEmpty) {
        throw const FormatException();
      }
      if (!canCommit()) throw ApiError(message: 'Sign-in was interrupted.');
      await PreferencesManager().saveToken(result.token);
      return result;
    } on FormatException {
      throw ApiError(message: 'Unable to read the Google sign-in response.');
    }
  }

  //login
  Future<AuthResponseModel> login(String email, String password) async {
    try {
      final deviceName = await _getDeviceName();
      final response = await _apiService.post('login', {
        'email': email,
        'password': password,
        'device_name': deviceName,
      });
      final responseMap = Map<String, dynamic>.from(response);
      if (response is Map<String, dynamic>) {
        final authResponse = AuthResponseModel.fromJson(responseMap);

        // Save token
        await PreferencesManager().saveToken(authResponse.token);

        return authResponse;
      } else {
        throw ApiError(message: 'Invalid response format');
      }
    } on DioException catch (e) {
      throw ApiExceptions.handleError(e);
    } catch (e) {
      throw ApiError(message: 'An unexpected error occurred: $e');
    }
  }

  Future<AuthResponseModel> register({
    required String email,
    required String password,
    required String passwordConfirmation,
    required bool termsAccepted,
    String? locale, // 'en' or 'ar', optional per docs
  }) async {
    try {
      final deviceName = await _getDeviceName();

      final response = await _apiService.post('register', {
        'email': email,
        'password': password,
        'password_confirmation': passwordConfirmation,
        'device_name': deviceName,
        'terms_accepted': termsAccepted,
        'locale': ?locale,
      });

      if (response is Map<String, dynamic>) {
        final authResponse = AuthResponseModel.fromJson(response);
        await PreferencesManager().saveToken(authResponse.token);
        return authResponse;
      } else {
        throw ApiError(message: 'Invalid response format');
      }
    } on ApiError {
      rethrow;
    } on DioException catch (e) {
      throw ApiExceptions.handleError(e);
    } catch (e) {
      throw ApiError(message: 'An unexpected error occurred: $e');
    }
  }

  Future<String> _getDeviceName() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      return '${info.manufacturer} ${info.model}';
    } else if (Platform.isIOS) {
      final info = await deviceInfo.iosInfo;
      return info
          .utsname
          .machine; // or info.name if you want the user-set device name
    }
    return 'unknown_device';
  }

  Future<void> verifyEmailCode({
    required String email,
    required String code,
  }) async {
    try {
      await _apiService.post('email/verify-code', {
        'email': email,
        'code': code,
      });
    } on DioException catch (e) {
      throw ApiExceptions.handleError(e);
    } catch (e) {
      throw ApiError(message: 'An unexpected error occurred: $e');
    }
  }

  /// Sends a password-reset code to the user's email.
  Future<void> forgotPassword({required String email}) async {
    try {
      await _apiService.post('forgot-password', {'email': email});
    } on DioException catch (e) {
      throw ApiExceptions.handleError(e);
    } catch (e) {
      throw ApiError(message: 'An unexpected error occurred: $e');
    }
  }

  Future<String> verifyResetCode({
    required String email,
    required String code,
  }) async {
    try {
      final response = await _apiService.post('email/verify-reset-code', {
        'email': email,
        'code': code,
      });

      if (response is Map<String, dynamic>) {
        final token = response['token']?.toString();
        if (token != null && token.isNotEmpty) {
          return token;
        }
        // Some APIs nest it under `data`
        final data = response['data'];
        if (data is Map<String, dynamic> && data['token'] != null) {
          return data['token'].toString();
        }
      }

      throw ApiError(message: 'No reset token returned by the server');
    } on DioException catch (e) {
      throw ApiExceptions.handleError(e);
    } catch (e) {
      throw ApiError(message: 'An unexpected error occurred: $e');
    }
  }

  Future<void> resetPassword({
    required String token,
    required String email,
    required String password,
    required String passwordConfirmation,
  }) async {
    try {
      await _apiService.post('reset-password', {
        'token': token,
        'email': email,
        'password': password,
        'password_confirmation': passwordConfirmation,
      });
    } on DioException catch (e) {
      throw ApiExceptions.handleError(e);
    } catch (e) {
      throw ApiError(message: 'An unexpected error occurred: $e');
    }
  }
}
