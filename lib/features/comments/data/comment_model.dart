import 'package:travibe/core/models/cursor_pagination.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/home/data/post_model.dart';

class CommentPermissions {
  const CommentPermissions({required this.canEdit, required this.canDelete});
  final bool canEdit;
  final bool canDelete;
}

class CommentModel {
  const CommentModel({
    required this.id,
    required this.postId,
    required this.parentId,
    required this.content,
    required this.permissions,
    this.user,
    this.media = const [],
    this.likesCount,
    this.isLiked,
    this.repliesCount,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });
  final int id;
  final int postId;
  final int? parentId;
  final String? content;
  final PublicUserModel? user;
  final List<PostMediaModel> media;
  final int? likesCount;
  final bool? isLiked;
  final int? repliesCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final CommentPermissions permissions;

  CommentModel copyWithLikes({
    required bool isLiked,
    required int likesCount,
  }) => CommentModel(
    id: id,
    postId: postId,
    parentId: parentId,
    content: content,
    permissions: permissions,
    user: user,
    media: media,
    likesCount: likesCount,
    isLiked: isLiked,
    repliesCount: repliesCount,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
  );

  factory CommentModel.fromJson(Map<String, dynamic> json) {
    final permissions = json['permissions'];
    if (json['id'] is! int ||
        json['post_id'] is! int ||
        !json.containsKey('parent_id') ||
        (json['parent_id'] != null && json['parent_id'] is! int) ||
        !json.containsKey('content') ||
        (json['content'] != null && json['content'] is! String) ||
        permissions is! Map ||
        permissions['can_edit'] is! bool ||
        permissions['can_delete'] is! bool) {
      throw ApiError(message: 'Invalid comment response');
    }
    return CommentModel(
      id: json['id'] as int,
      postId: json['post_id'] as int,
      parentId: json['parent_id'] as int?,
      content: json['content'] as String?,
      permissions: CommentPermissions(
        canEdit: permissions['can_edit'] as bool,
        canDelete: permissions['can_delete'] as bool,
      ),
      user: json['user'] is Map
          ? PublicUserModel.fromJson(Map<String, dynamic>.from(json['user']))
          : null,
      media: List.unmodifiable(
        (json['media'] as List? ?? []).map(
          (item) => PostMediaModel.fromJson(Map<String, dynamic>.from(item)),
        ),
      ),
      likesCount:
          json['likes_count'] is int && (json['likes_count'] as int) >= 0
          ? json['likes_count'] as int
          : null,
      isLiked: json['is_liked'] is bool ? json['is_liked'] as bool : null,
      repliesCount: json['replies_count'] as int?,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
      deletedAt: DateTime.tryParse(json['deleted_at']?.toString() ?? ''),
    );
  }
}

// The API uses exactly the same resource for comments and replies.
typedef ReplyModel = CommentModel;

class CommentTextRequest {
  const CommentTextRequest(this.content, {this.parentId});
  final String content;
  final int? parentId;

  String? get validationError => content.trim().isEmpty
      ? 'Enter a comment.'
      : content.trim().runes.length > 2000
      ? 'Comments must be 2000 characters or fewer.'
      : null;

  Map<String, dynamic> toJson() {
    final error = validationError;
    if (error != null) throw ApiError(message: error);
    return {
      'content': content.trim(),
      if (parentId != null) 'parent_id': parentId,
    };
  }
}

class CommentsPage {
  CommentsPage({required List<CommentModel> comments, required this.pagination})
    : comments = List.unmodifiable(comments);
  final List<CommentModel> comments;
  final CursorPaginationMeta pagination;
  bool get hasMore => pagination.hasMore;

  factory CommentsPage.fromJson(dynamic json) {
    final page = CursorPage<CommentModel>.fromJson(
      json,
      (item) => CommentModel.fromJson(Map<String, dynamic>.from(item)),
    );
    return CommentsPage(comments: page.items, pagination: page.pagination);
  }
}
