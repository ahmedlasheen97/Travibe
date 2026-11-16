import 'package:dio/dio.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';

class ApiExceptions {
  static ApiError handleError(DioException error) {
    switch (error.type) {
      case DioExceptionType.cancel:
        return ApiError(
          message: 'The request was cancelled. Please try again.',
        );

      case DioExceptionType.connectionTimeout:
        return ApiError(
          message: 'The connection timed out. Please try again.',
          isConnectionError: true,
          isTimeout: true,
        );

      case DioExceptionType.sendTimeout:
        return ApiError(
          message: 'The connection timed out. Please try again.',
          isTimeout: true,
        );

      case DioExceptionType.receiveTimeout:
        return ApiError(
          message: 'The server took too long to respond. Please try again.',
          isTimeout: true,
        );

      case DioExceptionType.transformTimeout:
        return ApiError(message: ApiError.fallbackMessage);

      case DioExceptionType.badResponse:
        return _handleBadResponse(error);

      case DioExceptionType.connectionError:
        return ApiError(
          message: 'No internet connection. Check your connection and retry.',
          isConnectionError: true,
        );

      case DioExceptionType.badCertificate:
        return ApiError(
          message: 'Unable to connect securely. Please try again.',
        );

      case DioExceptionType.unknown:
        return ApiError(message: ApiError.fallbackMessage);
    }
  }

  static ApiError _handleBadResponse(DioException error) {
    final response = error.response;

    if (response == null) {
      return ApiError(message: ApiError.fallbackMessage);
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
              : _nonEmpty(message) ?? ApiError.fallbackMessage,
          statusCode: response.statusCode,
          fieldErrors: Map.unmodifiable(fields),
        );
      }

      // 403
      if (response.statusCode == 403) {
        return ApiError(
          message: _nonEmpty(message) ?? ApiError.fallbackMessage,
          statusCode: response.statusCode,
        );
      }

      // Other errors
      return ApiError(
        message: _nonEmpty(message) ?? ApiError.fallbackMessage,
        statusCode: response.statusCode,
      );
    }

    // If API returned a String instead of JSON
    if (data is String && data.isNotEmpty) {
      // Raw bodies (HTML error pages, stack traces) are not user-facing.
      return ApiError(
        message: ApiError.fallbackMessage,
        statusCode: response.statusCode,
      );
    }

    return ApiError(
      message: ApiError.fallbackMessage,
      statusCode: response.statusCode,
    );
  }

  static String? _nonEmpty(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
