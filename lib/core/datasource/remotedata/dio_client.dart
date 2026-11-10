import 'package:dio/dio.dart';
import 'buddies_diagnostics.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';

class DioClient {
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl:
          'https://travibeapp.com/api/v1/', // Replace with your API base URL
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );
  DioClient() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Device-token operations carry a captured principal, including stale
          // logout cleanup. Never replace its Authorization with another user.
          if (options.extra['capturedDeviceTokenCredentials'] == true &&
              RegExp(
                r'^device-tokens(?:/[1-9][0-9]*)?$',
              ).hasMatch(options.path) &&
              options.headers['Authorization'] is String) {
            return handler.next(options);
          }
          final expectedSession = options.extra['sessionRevision'];
          final token = await PreferencesManager().getToken();
          if (expectedSession != null &&
              expectedSession != PreferencesManager().sessionRevision) {
            return handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.cancel,
                message: 'The account session changed.',
              ),
            );
          }
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onResponse: (response, handler) {
          if (response.requestOptions.extra['sensitiveAccountDeletion'] ==
              true) {
            response.requestOptions.queryParameters.clear();
          }
          logBuddiesResponse(response);
          // Handle successful responses here
          return handler.next(response);
        },
        onError: (DioException error, handler) {
          if (error.requestOptions.extra['sensitiveAccountDeletion'] == true) {
            error.requestOptions.queryParameters.clear();
          }
          logBuddiesResponse(error.response, request: error.requestOptions);
          // Handle errors here
          return handler.next(error);
        },
      ),
    );
  }
  Dio get dio => _dio;
}
