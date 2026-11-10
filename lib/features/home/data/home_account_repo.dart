import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';

int? _nonNegativeCount(dynamic value) {
  final count = value is int
      ? value
      : value is String && RegExp(r'^\d+$').hasMatch(value.trim())
      ? int.tryParse(value.trim())
      : null;
  return count != null && count >= 0 ? count : null;
}

class HomeAccount {
  const HomeAccount({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.followingCount,
  });
  final String id;
  final String name;
  final String? avatarUrl;
  // Missing counts must never be interpreted as zero relationships.
  final int? followingCount;

  factory HomeAccount.fromJson(dynamic response) {
    var data = response is Map ? response['data'] : null;
    // Tolerate a second data envelope; the documented shape is data: UserResource.
    if (data is Map && !data.containsKey('id') && data['data'] is Map) {
      data = data['data'];
    }
    if (data is! Map || data['id'] is! int || data['name'] is! String) {
      throw ApiError(message: 'Unable to read your account. Please try again.');
    }
    // Accept integer strings without rounding fractional values or treating
    // absent/malformed counts as zero relationships.
    final count = _nonNegativeCount(data['following_count']);
    return HomeAccount(
      id: data['id'].toString(),
      name: data['name'] as String,
      avatarUrl: data['avatar_url'] is String
          ? data['avatar_url'] as String
          : null,
      followingCount: count,
    );
  }
}

class HomeAccountRepo {
  HomeAccountRepo({ApiService? apiService}) : _api = apiService ?? ApiService();
  final ApiService _api;
  Future<HomeAccount> getAccount() async {
    final account = HomeAccount.fromJson(await _api.get('user'));
    if (account.followingCount != null) return account;

    // Only need pagination metadata, not the full list of followed profiles.
    final response = await _api.get(
      'users/${account.id}/following-list',
      queryParameters: {'per_page': 1},
    );
    final meta = response is Map ? response['meta'] : null;
    final count = meta is Map ? _nonNegativeCount(meta['total']) : null;
    if (count == null) {
      throw ApiError(
        message: 'Unable to load your following count. Please try again.',
      );
    }
    return HomeAccount(
      id: account.id,
      name: account.name,
      avatarUrl: account.avatarUrl,
      followingCount: count,
    );
  }
}
