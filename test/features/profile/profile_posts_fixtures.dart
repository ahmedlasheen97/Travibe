import '../../helpers/cursor_fixtures.dart';
import 'dart:async';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/home/data/posts_page_model.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'package:travibe/features/profile/data/profile_repo.dart';
import '../saved/fixtures.dart';
import 'fixtures.dart';

Map<String, dynamic> authorPostJson(int id, int userId, {bool viewer = true}) =>
    {
      ...savedPostJson(id, saved: false),
      'user_id': userId,
      'user': {'id': userId, 'name': 'Author $userId'},
      'content': 'Author $userId post $id',
      if (!viewer) 'is_saved': null,
      if (!viewer) 'is_liked': null,
    };
PostModel authorPost(int id, int userId) =>
    PostModel.fromJson(authorPostJson(id, userId));
PostsPageModel authorPage(
  int userId,
  List<int> ids, {
  int page = 1,
  int last = 1,
}) => PostsPageModel(
  pagination: fixtureMeta(current: page, last: last),

  posts: ids.map((id) => authorPost(id, userId)).toList(),
  currentPage: page,
  lastPage: last,
  total: ids.length,
);

class AuthorRead {
  AuthorRead(this.userId, this.page);
  final int userId;
  final int page;
  final result = Completer<PostsPageModel>();
}

class AuthorPostsRepo extends SavedRepo {
  final authorReads = <AuthorRead>[];
  bool holdAuthors = false;
  Object? authorError;
  int authorLast = 1;
  Map<int, List<int>> authors = {
    7: [101],
    23: [201],
    42: [301],
  };
  @override
  Future<PostsPageModel> getUserPosts({
    required int userId,
    String? cursor,
    int perPage = 15,
  }) async {
    final page = fixturePage(cursor);
    final read = AuthorRead(userId, page);
    authorReads.add(read);
    if (holdAuthors) return read.result.future;
    if (authorError != null) throw authorError!;
    return authorPage(
      userId,
      authors[userId] ?? [],
      page: page,
      last: authorLast,
    );
  }
}

class AuthorProfilesRepo extends ProfileRepo {
  int ownId = 7;
  Set<int> unavailable = {};
  @override
  Future<ProfileModel> getMyProfile() async =>
      profile(id: ownId, name: 'Owner $ownId');
  @override
  Future<ProfileModel?> getPublicProfile(int userId) async =>
      unavailable.contains(userId)
      ? null
      : profile(id: userId, name: 'Public $userId');
}
