import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_exceptions.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/search/data/recent_search.dart';
import 'package:travibe/features/search/data/users_page_model.dart';
import 'package:travibe/features/home/data/home_account_repo.dart';

class SearchRepo {
  SearchRepo({ApiService? apiService})
    : _apiService = apiService ?? ApiService();
  final ApiService _apiService;

  /// Per-account key prefix; removed by [PreferencesManager.clearSession].
  static const String recentKeyPrefix = 'recent_searches_';
  static const String _legacyRecentKey = 'recent_searches';
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

  Future<String>? _userId;
  int? _userIdRevision;

  /// The signed-in user's id, shared by callers within one session.
  Future<String> getCurrentUserId() {
    final revision = PreferencesManager().sessionRevision;
    if (_userId != null && _userIdRevision == revision) return _userId!;
    _userIdRevision = revision;
    final request = _apiService
        .get('user')
        .then((json) => HomeAccount.fromJson(json).id);
    _userId = request;
    request.catchError((_) {
      if (identical(_userId, request)) _userId = null;
      return '';
    });
    return request;
  }

  // ---------------- recent searches (local, per account) ----------------

  List<RecentSearch> getRecentSearches(String userId) {
    final raw = PreferencesManager().getString('$recentKeyPrefix$userId');
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map(RecentSearch.fromJson)
          .whereType<RecentSearch>()
          .take(maxRecent)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveRecentSearches(
    String userId,
    List<RecentSearch> items,
  ) async {
    final preferences = PreferencesManager();
    // The old shared key had no owner, so it is dropped rather than migrated.
    if (preferences.getString(_legacyRecentKey) != null) {
      await preferences.remove(_legacyRecentKey);
    }
    await preferences.setString(
      '$recentKeyPrefix$userId',
      jsonEncode([for (final item in items) item.toJson()]),
    );
  }
}
