import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Allowlist only. Never print headers, full URLs, credentials or raw bodies.
void logBuddiesResponse(
  Response<dynamic>? response, {
  RequestOptions? request,
}) {
  if (!kDebugMode) return;
  final options = request ?? response?.requestOptions;
  if (options == null) return;
  final path = options.uri.path;
  if (!(path.endsWith('/profile/location') || path.contains('/buddies/'))) {
    return;
  }
  final emptySearch =
      path.endsWith('/buddies/search') &&
      response?.statusCode == 200 &&
      response?.data is Map &&
      response?.data['data'] is List &&
      (response!.data['data'] as List).isEmpty;
  if (response?.statusCode != 422 && !emptySearch) return;
  final data = <String, dynamic>{
    ...options.uri.queryParametersAll,
    ...options.queryParameters,
    if (options.data is Map) ...Map<String, dynamic>.from(options.data),
  };
  final safe = <String, dynamic>{};
  for (final key in [
    'location',
    'city',
    'country_code',
    'gender[]',
    'nationality[]',
    'languages[]',
    'interests[]',
    'travel_styles[]',
    'page',
    'per_page',
  ]) {
    final value = data[key];
    if (value is String ||
        value is num ||
        value is List && value.every((item) => item is String)) {
      safe[key] = value;
    }
  }
  var id =
      response?.headers.value('x-request-id') ??
      response?.headers.value('request-id');
  if (id == null &&
      response?.data is Map &&
      response?.data['request_id'] is String) {
    id = response?.data['request_id'];
  }
  if (id != null && !RegExp(r'^[a-zA-Z0-9_.:-]{1,128}$').hasMatch(id)) {
    id = '<redacted>';
  }
  debugPrint(
    '[Buddies] ${options.method} $path status=${response?.statusCode} empty=$emptySearch payload=${jsonEncode(safe)} requestId=${id ?? 'unavailable'}',
  );
}
