import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/home/data/post_model.dart';

enum SharePlatform {
  internal('internal'),
  facebook('facebook'),
  twitter('twitter'),
  linkedin('linkedin'),
  whatsapp('whatsapp'),
  email('email'),
  copyLink('copy_link');

  const SharePlatform(this.value);
  final String value;
}

class CreateShareRequest {
  const CreateShareRequest({
    this.platform = SharePlatform.internal,
    this.comment,
  });
  final SharePlatform platform;
  final String? comment;
  String? get validationError => (comment?.trim().runes.length ?? 0) > 500
      ? 'Share notes must be 500 characters or fewer.'
      : null;
  Map<String, dynamic> toJson() {
    if (validationError != null) throw ApiError(message: validationError!);
    final note = comment?.trim();
    return {
      'platform': platform.value,
      'comment': note == null || note.isEmpty ? null : note,
    };
  }
}

class ShareModel {
  const ShareModel({
    required this.id,
    required this.userId,
    required this.postId,
    required this.platform,
    this.comment,
    this.user,
    this.repost,
    this.createdAt,
    this.updatedAt,
  });
  final int id;
  final int userId;
  final int postId;
  final SharePlatform platform;
  final String? comment;
  final PublicUserModel? user;
  final PostModel? repost;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ShareModel.fromJson(dynamic json) {
    if (json is! Map ||
        json['id'] is! int ||
        (json['id'] as int) < 1 ||
        json['user_id'] is! int ||
        (json['user_id'] as int) < 1 ||
        json['post_id'] is! int ||
        (json['post_id'] as int) < 1 ||
        !json.containsKey('comment') ||
        (json['comment'] != null && json['comment'] is! String)) {
      throw ApiError(
        message:
            'Unable to read the share response. Please check your share status before retrying.',
      );
    }
    final platforms = SharePlatform.values.where(
      (p) => p.value == json['platform'],
    );
    if (platforms.isEmpty) {
      throw ApiError(message: 'Invalid share platform response.');
    }
    return ShareModel(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      postId: json['post_id'] as int,
      platform: platforms.single,
      comment: json['comment'] as String?,
      user: json['user'] is Map
          ? PublicUserModel.fromJson(Map<String, dynamic>.from(json['user']))
          : null,
      repost: json['repost'] is Map
          ? PostModel.fromJson(Map<String, dynamic>.from(json['repost']))
          : null,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
    );
  }
}

class SharesPage {
  SharesPage({
    required List<ShareModel> shares,
    required this.currentPage,
    required this.lastPage,
    required this.total,
  }) : shares = List.unmodifiable(shares);
  final List<ShareModel> shares;
  final int currentPage;
  final int lastPage;
  final int total;
  bool get hasMore => currentPage < lastPage;
  factory SharesPage.fromJson(dynamic json) {
    final meta = json is Map ? json['meta'] : null;
    if (json is! Map ||
        json['data'] is! List ||
        meta is! Map ||
        meta['current_page'] is! int ||
        (meta['current_page'] as int) < 1 ||
        meta['last_page'] is! int ||
        (meta['last_page'] as int) < 1 ||
        meta['total'] is! int ||
        (meta['total'] as int) < 0) {
      throw ApiError(message: 'Unable to read shares. Please try again.');
    }
    return SharesPage(
      shares: (json['data'] as List).map(ShareModel.fromJson).toList(),
      currentPage: meta['current_page'] as int,
      lastPage: meta['last_page'] as int,
      total: meta['total'] as int,
    );
  }
}
