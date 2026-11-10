import 'package:dio/dio.dart';
import 'package:travibe/core/datasource/remotedata/dio_client.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'push_device_store.dart';
import 'push_token_repository.dart';

/// Uses the existing Dio interceptors, but freezes Authorization per operation.
/// Errors use fixed messages: server validation bodies can echo secret tokens.
class LaravelPushTokenRepository implements PushTokenRepository {
  LaravelPushTokenRepository({DioClient? client, PushDeviceStore? store})
    : _client = client ?? DioClient(),
      _store = store ?? PushDeviceStore() {
    _client.dio.options.connectTimeout = const Duration(seconds: 10);
  }
  final DioClient _client;
  final PushDeviceStore _store;
  @override
  bool get supported => true;

  Options _options(PushAccount account) => Options(
    headers: {
      'Authorization': 'Bearer ${account.authorizationToken}',
      'Content-Type': 'application/json',
    },
    extra: {'capturedDeviceTokenCredentials': true},
    followRedirects: false,
    sendTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  );
  static String? _id(Object? value) {
    final text = value is int || value is String ? value.toString() : '';
    return RegExp(r'^[1-9][0-9]*$').hasMatch(text) ? text : null;
  }

  @override
  Future<PushDeviceRecord> register(PushRegistration registration) async {
    final platform = registration.platform.toLowerCase();
    if (!{'ios', 'android'}.contains(platform) ||
        registration.token.trim().isEmpty ||
        registration.token != registration.token.trim()) {
      throw ApiError(message: 'Unsupported notification device.');
    }
    try {
      final response = await _client.dio.post<dynamic>(
        'device-tokens',
        data: {'token': registration.token, 'platform': platform},
        options: _options(registration.account),
      );
      final data = response.data is Map ? response.data['data'] : null;
      final id = data is Map ? _id(data['id']) : null;
      if (response.statusCode == null ||
          response.statusCode! < 200 ||
          response.statusCode! >= 300 ||
          id == null ||
          data['platform'] != platform) {
        throw ApiError(
          message: 'Unable to confirm device registration. Please retry.',
        );
      }
      final record = PushDeviceRecord(id: id, registration: registration);
      await _store.remember(registration.account.userId, id);
      return record;
    } on DioException catch (error) {
      throw _failure(error.response?.statusCode);
    }
  }

  @override
  Future<void> unregister(PushDeviceRecord record) =>
      _revoke(record.registration.account, record.id);

  Future<void> _revoke(PushAccount account, String id) async {
    if (_id(id) == null) throw ApiError(message: 'Invalid device record.');
    try {
      final response = await _client.dio.delete<dynamic>(
        'device-tokens/$id',
        options: _options(account),
      );
      if (response.statusCode != 204) {
        throw ApiError(
          message: 'Unable to confirm device removal. Please retry.',
        );
      }
    } on DioException catch (error) {
      // Account-scoped absence is successful cleanup, never a reason to retry
      // with the active account's credentials or a raw FCM token URL.
      if (error.response?.statusCode != 404) {
        throw _failure(error.response?.statusCode);
      }
    }
    await _store.forget(account.userId, id);
  }

  @override
  Future<void> cleanup(PushAccount account, {String? exceptId}) async {
    for (final id in _store.ids(account.userId)) {
      if (id != exceptId) await _revoke(account, id);
    }
  }

  static ApiError _failure(int? status) => ApiError(
    statusCode: status,
    message: status == 401
        ? 'Sign in again to synchronize notifications.'
        : status == 403
        ? 'Verify your email and account access to enable notifications.'
        : 'Unable to synchronize notifications. Please retry.',
  );
}
