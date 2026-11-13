import 'package:dio/dio.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';

class ApiExceptions {
  static ApiError handleError(DioException error) {
    switch (error.type) {
      case DioExceptionType.cancel:
        return ApiError(message: 'Request to API server was cancelled');

      case DioExceptionType.connectionTimeout:
        return ApiError(
          message: 'Connection timeout with API server',
          isConnectionError: true,
          isTimeout: true,
        );

      case DioExceptionType.sendTimeout:
        return ApiError(
          message: 'Send timeout in connection with API server',
          isTimeout: true,
        );

      case DioExceptionType.receiveTimeout:
        return ApiError(
          message: 'Receive timeout with API server',
          isTimeout: true,
        );

      case DioExceptionType.transformTimeout:
        return ApiError(message: 'Response transformation timeout');

      case DioExceptionType.badResponse:
        return _handleBadResponse(error);

      case DioExceptionType.connectionError:
        return ApiError(
          message:
              'Connection to API server failed. Check your internet connection.',
          isConnectionError: true,
        );

      case DioExceptionType.badCertificate:
        return ApiError(message: 'Bad SSL certificate');

      case DioExceptionType.unknown:
        return ApiError(message: 'Unexpected error occurred');
    }
  }

  static ApiError _handleBadResponse(DioException error) {
    final response = error.response;

    if (response == null) {
      return ApiError(message: 'No response from server');
    }

    final data = response.data;

    // Make sure response is a Map before accessing ['message']
    if (data is Map<String, dynamic>) {
      final message = data['message']?.toString();

      // 422 Validation Error
      if (response.statusCode == 422) {
        final errors = data['errors'];

        final fields = <String, List<String>>{};
        if (errors is Map) {
          for (final entry in errors.entries) {
            final value = entry.value;
            if (value is List && value.isNotEmpty) {
              fields[entry.key.toString()] = List.unmodifiable(
                value.map((e) => e.toString()),
              );
            }
          }
        }
        return ApiError(
          message: fields.isNotEmpty
              ? fields.values.first.first
              : message ?? 'Validation failed',
          statusCode: response.statusCode,
          fieldErrors: Map.unmodifiable(fields),
        );
      }

      // 403
      if (response.statusCode == 403) {
        return ApiError(
          message: message ?? 'Forbidden',
          statusCode: response.statusCode,
        );
      }

      // Other errors
      return ApiError(
        message:
            message ?? 'Received invalid status code: ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    // If API returned a String instead of JSON
    if (data is String && data.isNotEmpty) {
      return ApiError(message: data, statusCode: response.statusCode);
    }

    return ApiError(
      message: 'Received invalid status code: ${response.statusCode}',
      statusCode: response.statusCode,
    );
  }
}
