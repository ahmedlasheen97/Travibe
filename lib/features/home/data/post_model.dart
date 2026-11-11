import 'package:travibe/core/utils/json_parsers.dart';

class PostAuthorModel {
  final String id;
  final String name;
  final String? username;
  final String? countryCode;
  final String? avatarUrl;
  final bool isFollowing;
  final bool isBlocked;
  final int followersCount;
  final int followingCount;

  const PostAuthorModel({
    required this.id,
    required this.name,
    this.username,
    this.countryCode,
    this.avatarUrl,
    required this.isFollowing,
    required this.isBlocked,
    required this.followersCount,
    required this.followingCount,
  });

  factory PostAuthorModel.fromJson(Map<String, dynamic> json) {
    return PostAuthorModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      username: json['username']?.toString(),
      countryCode: json['country_code']?.toString(),
      avatarUrl: json['avatar_url']?.toString(),
      isFollowing: parseBool(json['is_following']),
      isBlocked: parseBool(json['is_blocked']),
      followersCount: parseInt(json['followers_count']),
      followingCount: parseInt(json['following_count']),
    );
  }
}

class PostMediaModel {
  final String id;
  final String url;
  final String thumbnailUrl;
  final String? mimeType;
  final int? width;
  final int? height;

  const PostMediaModel({
    required this.id,
    required this.url,
    required this.thumbnailUrl,
    this.mimeType,
    this.width,
    this.height,
  });

  bool get isVideo => mimeType?.startsWith('video/') ?? false;

  /// What the feed should show: the thumbnail for videos, the image otherwise.
  String get displayUrl =>
      isVideo && thumbnailUrl.isNotEmpty ? thumbnailUrl : url;

  factory PostMediaModel.fromJson(Map<String, dynamic> json) {
    return PostMediaModel(
      id: json['id']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      thumbnailUrl: json['thumbnail_url']?.toString() ?? '',
      mimeType: json['mime_type']?.toString(),
      width: int.tryParse(json['width']?.toString() ?? ''),
      height: int.tryParse(json['height']?.toString() ?? ''),
    );
  }
}

class PostModel {
  final String id;
  final String type;
  final String userId;
  final PostAuthorModel user;
  final String? content;
  final List<PostMediaModel> media;
  final String visibility;
  final int likesCount;
  final int commentsCount;
  final bool hasCommentCount;
  final bool isPinned;
  final bool commentsDisabled;
  final PostModel? originalPost;
  final bool originalPostUnavailable;
  final bool isLiked;
  // Optional viewer fields must be present before inferring a toggle direction.
  final bool hasLikeState;
  final bool isSaved;
  final bool hasSaveState;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Share link from `PostResource.url` (https only).
  final Uri? url;

  /// [url], or the documented `https://travibeapp.com/p/{id}` form when an
  /// older payload omits it.
  Uri get shareUri => url ?? Uri.https('travibeapp.com', '/p/$id');

  const PostModel({
    required this.id,
    required this.type,
    required this.userId,
    required this.user,
    this.content,
    required this.media,
    required this.visibility,
    required this.likesCount,
    required this.commentsCount,
    this.hasCommentCount = true,
    required this.isPinned,
    required this.commentsDisabled,
    this.originalPost,
    required this.originalPostUnavailable,
    required this.isLiked,
    this.hasLikeState = true,
    required this.isSaved,
    this.hasSaveState = true,
    this.createdAt,
    this.updatedAt,
    this.url,
  });

  factory PostModel.fromJson(Map<String, dynamic> json) {
    final originalPostJson = json['original_post'];
    final mediaJson = json['media'];

    return PostModel(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      user: PostAuthorModel.fromJson(
        Map<String, dynamic>.from(json['user'] ?? {}),
      ),
      content: json['content']?.toString(),
      media: mediaJson is List
          ? mediaJson
                .map(
                  (e) => PostMediaModel.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList()
          : const [],
      visibility: json['visibility']?.toString() ?? '',
      likesCount: parseInt(json['likes_count']),
      commentsCount: parseInt(json['comments_count']),
      hasCommentCount:
          json['comments_count'] is int && (json['comments_count'] as int) >= 0,
      isPinned: parseBool(json['is_pinned']),
      commentsDisabled: parseBool(json['comments_disabled']),
      originalPost: originalPostJson is Map
          ? PostModel.fromJson(Map<String, dynamic>.from(originalPostJson))
          : null,
      originalPostUnavailable: parseBool(json['original_post_unavailable']),
      isLiked: parseBool(json['is_liked']),
      hasLikeState:
          json['is_liked'] is bool &&
          json['likes_count'] is int &&
          (json['likes_count'] as int) >= 0,
      isSaved: parseBool(json['is_saved']),
      hasSaveState: json['is_saved'] is bool,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
      url: _httpsUri(json['url']),
    );
  }

  static Uri? _httpsUri(Object? value) {
    final uri = value is String ? Uri.tryParse(value) : null;
    return uri != null &&
            uri.scheme == 'https' &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty
        ? uri
        : null;
  }

  /// Update interaction fields without replacing the post's content.
  PostModel copyWith({
    bool? isLiked,
    bool? isSaved,
    bool? hasSaveState,
    int? likesCount,
    int? commentsCount,
    bool? hasCommentCount,
    bool? hasLikeState,
    bool? commentsDisabled,
  }) {
    return PostModel(
      id: id,
      type: type,
      userId: userId,
      user: user,
      content: content,
      media: media,
      visibility: visibility,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      hasCommentCount: hasCommentCount ?? this.hasCommentCount,
      isPinned: isPinned,
      commentsDisabled: commentsDisabled ?? this.commentsDisabled,
      originalPost: originalPost,
      originalPostUnavailable: originalPostUnavailable,
      isLiked: isLiked ?? this.isLiked,
      hasLikeState: hasLikeState ?? this.hasLikeState,
      isSaved: isSaved ?? this.isSaved,
      hasSaveState: hasSaveState ?? this.hasSaveState,
      createdAt: createdAt,
      updatedAt: updatedAt,
      url: url,
    );
  }
}
