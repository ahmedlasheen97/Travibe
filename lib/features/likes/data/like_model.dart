import 'package:travibe/core/datasource/remotedata/api_error.dart';

class LikeTarget {
  const LikeTarget.post(this.postId) : commentId = null;
  const LikeTarget.comment(this.postId, int id) : commentId = id;
  final int postId;
  final int? commentId;

  String get path =>
      commentId == null ? 'posts/$postId' : 'posts/$postId/comments/$commentId';

  @override
  bool operator ==(Object other) =>
      other is LikeTarget &&
      other.postId == postId &&
      other.commentId == commentId;
  @override
  int get hashCode => Object.hash(postId, commentId);
}

class LikeValue {
  const LikeValue({
    required this.isLiked,
    required this.count,
    this.pending = false,
  });
  final bool isLiked;
  final int count;
  final bool pending;

  factory LikeValue.fromJson(dynamic json) {
    if (json is! Map ||
        json['is_liked'] is! bool ||
        json['likes_count'] is! int ||
        (json['likes_count'] as int) < 0) {
      throw ApiError(
        message: 'Unable to read the like response. Please try again.',
      );
    }
    return LikeValue(
      isLiked: json['is_liked'] as bool,
      count: json['likes_count'] as int,
    );
  }
}
