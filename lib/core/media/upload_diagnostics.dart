import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';

enum UploadDiagnosticStage {
  validation,
  presign,
  storage,
  finalize,
  polling,
  profilePatch,
  profileRefresh,
}

/// Deliberately logs fixed categories/status codes only. Never interpolate raw
/// exceptions, stack traces, response bodies, request options or user input.
void logUploadFailure(
  UploadDiagnosticStage stage,
  Object error, {
  Duration? elapsed,
}) {
  if (!kDebugMode) return;
  final category = switch (error) {
    DioException() => 'transport_${error.type.name}',
    TimeoutException() => 'timeout',
    FormatException() => 'invalid_response',
    ApiError() => 'api_or_validation',
    _ => 'unexpected',
  };
  final status = switch (error) {
    DioException() => error.response?.statusCode,
    ApiError() => error.statusCode,
    _ => null,
  };
  debugPrint(
    'Avatar upload failed: stage=${stage.name} category=$category http=${status ?? 'none'} elapsed_ms=${elapsed?.inMilliseconds ?? 'none'}',
  );
}

/// Request-specific diagnostics are temporary/opt-in and debug-only. Only known
/// schema keys, value types and the four documented media status values appear.
void logUploadRequest(
  UploadDiagnosticStage stage,
  Response<dynamic>? response,
  Object? error,
  Duration elapsed,
) {
  if (!kDebugMode) return;
  final rawType = response?.headers
      .value('content-type')
      ?.split(';')
      .first
      .trim()
      .toLowerCase();
  final type = switch (rawType) {
    'application/json' ||
    'application/problem+json' ||
    'text/json' ||
    'text/plain' ||
    'text/html' ||
    'application/xml' ||
    'text/xml' ||
    'application/octet-stream' => rawType,
    null => 'none',
    _ => 'other',
  };
  final category = switch (error) {
    null => 'none',
    DioException() => 'transport_${error.type.name}',
    TimeoutException() => 'timeout',
    FormatException() => 'invalid_response',
    ApiError() => 'api_or_validation',
    _ => 'unexpected',
  };
  debugPrint(
    'Avatar request: stage=${stage.name} http=${response?.statusCode ?? 'none'} '
    'type=$type shape=${_safeShape(response?.data)} category=$category elapsed_ms=${elapsed.inMilliseconds}',
  );
}

String _safeShape(dynamic data, [int depth = 0]) {
  if (data == null) return 'null';
  if (data is Map) {
    if (depth > 2) return 'object';
    const allowed = {
      'data',
      'media',
      'id',
      'status',
      'type',
      'mime_type',
      'original_name',
      'size',
      'url',
      'thumbnail_url',
      'expires_at',
      'upload_url',
      'upload_method',
      'upload_headers',
      'message',
      'errors',
      'success',
      'error',
      'width',
      'height',
      'created_at',
      'updated_at',
    };
    final keys = data.keys.whereType<String>().where(allowed.contains).toList()
      ..sort();
    final fields = [
      for (final key in keys)
        '$key:${key == 'upload_headers'
            ? 'redacted'
            : key == 'status' && ['pending', 'processing', 'ready', 'failed'].contains(data[key])
            ? data[key]
            : _safeShape(data[key], depth + 1)}',
    ];
    if (data.length > keys.length) {
      fields.add('other_keys:${data.length - keys.length}');
    }
    return '{${fields.join(',')}}';
  }
  if (data is List) return 'array';
  if (data is int) return 'integer';
  if (data is num) return 'number';
  if (data is bool) return 'boolean';
  if (data is String) {
    if (depth == 0 && data.length <= 65536) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map || decoded is List) {
          return 'json_string:${_safeShape(decoded, 1)}';
        }
      } on FormatException {
        /* Never log the text or parsing error. */
      }
    }
    return data.isEmpty ? 'empty_string' : 'string';
  }
  return 'other';
}

void observeMediaApiRequest(
  String method,
  String endpoint,
  Response<dynamic>? response,
  Object? failure,
  Duration elapsed,
) {
  final stage = endpoint == 'media/presign'
      ? UploadDiagnosticStage.presign
      : RegExp(r'^media/\d+/finalize$').hasMatch(endpoint)
      ? UploadDiagnosticStage.finalize
      : RegExp(r'^media/\d+$').hasMatch(endpoint)
      ? UploadDiagnosticStage.polling
      : null;
  if (stage != null) logUploadRequest(stage, response, failure, elapsed);
}

void observeProfileApiRequest(
  String method,
  String endpoint,
  Response<dynamic>? response,
  Object? failure,
  Duration elapsed,
) {
  if (endpoint != 'profile') return;
  if (method == 'PATCH' || method == 'GET') {
    logUploadRequest(
      method == 'PATCH'
          ? UploadDiagnosticStage.profilePatch
          : UploadDiagnosticStage.profileRefresh,
      response,
      failure,
      elapsed,
    );
  }
}
