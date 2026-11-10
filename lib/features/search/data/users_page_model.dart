import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/utils/json_parsers.dart';

class UsersPageModel {
  final List<PublicUserModel> users;
  final int currentPage;
  final int lastPage;
  final int total;

  const UsersPageModel({
    required this.users,
    required this.currentPage,
    required this.lastPage,
    required this.total,
  });

  bool get hasMore => currentPage < lastPage;

  factory UsersPageModel.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    if (data is! List ||
        json['meta'] is! Map ||
        data.any(
          (item) =>
              item is! Map || item['id'] is! int || (item['id'] as int) < 1,
        )) {
      throw ApiError(
        message: 'Unable to read the user search/list response. Please retry.',
      );
    }
    final meta = Map<String, dynamic>.from(json['meta'] ?? {});

    return UsersPageModel(
      users: data
          .map((e) => PublicUserModel.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      currentPage: parseInt(meta['current_page'], fallback: 1),
      lastPage: parseInt(meta['last_page'], fallback: 1),
      total: parseInt(meta['total']),
    );
  }
}
