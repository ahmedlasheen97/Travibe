import 'dart:async';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/cursor_pagination.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';
import 'package:travibe/features/likes/data/like_model.dart';
import 'package:travibe/features/likes/data/likes_repo.dart';

PublicUserModel liker(int id, {bool following = false}) =>
    PublicUserModel.fromJson({
      'id': id,
      'name': 'User $id',
      'username': 'user$id',
      'is_following': following,
      'followers_count': 1,
      'following_count': 1,
    });

/// Serves [pages] in order through opaque cursors; [error] fails the next read.
class LikersRepo extends LikesRepo {
  LikersRepo(this.pages);
  final List<List<PublicUserModel>> pages;
  final requests = <({LikeTarget target, String? cursor})>[];
  ApiError? error;
  Completer<void>? gate;

  @override
  Future<CursorPage<PublicUserModel>> list(
    LikeTarget target, {
    String? cursor,
    int perPage = 15,
  }) async {
    requests.add((target: target, cursor: cursor));
    if (gate != null) await gate!.future;
    if (error != null) {
      final failure = error!;
      error = null;
      throw failure;
    }
    final index = cursor == null ? 0 : int.parse(cursor.substring(5));
    return CursorPage(
      items: pages.isEmpty ? const [] : pages[index],
      pagination: CursorPaginationMeta(
        path: 'posts/${target.postId}/likes',
        perPage: perPage,
        nextCursor: index + 1 < pages.length ? 'page-${index + 1}' : null,
        prevCursor: null,
      ),
    );
  }
}

class FollowWrites extends FollowRepo {
  final requests = <String>[];
  @override
  Future<PublicUserModel> setFollowing(String id, bool following) async {
    requests.add(id);
    return liker(int.parse(id), following: following);
  }
}
