import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_exceptions.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/search/data/users_page_model.dart';
import 'package:travibe/features/home/data/home_account_repo.dart';

class SearchRepo {
  SearchRepo({ApiService? apiService})
    : _apiService = apiService ?? ApiService();
  final ApiService _apiService;

  static const String _recentKey = 'recent_searches';
  static const int maxRecent = 10;

  // ---------------- API ----------------

  Future<UsersPageModel> searchUsers(String query, {int page = 1}) async {
    final term = query.trim();
    if (term.runes.length < 3 || term.runes.length > 100 || page < 1) {
      throw ApiError(message: 'Search must contain 3–100 characters.');
    }
    try {
      final response = await _apiService.get(
        'search/users',
        queryParameters: {'q': term, 'page': page},
      );

      if (response is Map<String, dynamic> &&
          response['data'] is List &&
          response['meta'] is Map) {
        if ((response['data'] as List).any(
          (item) => item is! Map || item['name'] is! String,
        )) {
          throw ApiError(
            message: 'Unable to read the user search response. Please retry.',
          );
        }
        return UsersPageModel.fromJson(response);
      } else {
        throw ApiError(message: 'Invalid response format');
      }
    } on ApiError {
      rethrow;
    } on DioException catch (e) {
      throw ApiExceptions.handleError(e);
    } catch (_) {
      throw ApiError(message: 'Unable to search people. Please try again.');
    }
  }

  Future<String> getCurrentUserId() async =>
      HomeAccount.fromJson(await _apiService.get('user')).id;

  // ---------------- recent searches (local) ----------------

  List<String> getRecentSearches() {
    final raw = PreferencesManager().getString(_recentKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return List<String>.from(jsonDecode(raw) as List);
    } catch (_) {
      return [];
    }
  }

  Future<void> saveRecentSearches(List<String> items) async {
    await PreferencesManager().setString(_recentKey, jsonEncode(items));
  }
}
