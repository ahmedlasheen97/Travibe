import '../../helpers/cursor_fixtures.dart';
import 'dart:async';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/home/data/posts_page_model.dart';
import 'package:travibe/features/home/data/posts_repo.dart';

Map<String, dynamic> savedPostJson(int id, {bool saved = true}) => {
  'id': id,
  'user_id': 9,
  'type': 'post',
  'content': 'Saved post $id',
  'user': {'id': 9, 'name': 'Traveler'},
  'media': <dynamic>[],
  'visibility': 'public',
  'is_saved': saved,
  'is_liked': false,
  'likes_count': 2,
  'comments_count': 0,
  'shares_count': 0,
};
PostModel savedPost(int id, {bool saved = true}) =>
    PostModel.fromJson(savedPostJson(id, saved: saved));
PostsPageModel savedPage(List<int> ids, {int page = 1, int last = 1}) =>
    PostsPageModel(
      posts: ids.map((id) => savedPost(id)).toList(),
      currentPage: page,
      lastPage: last,
      total: ids.length,
    );
Map<String, dynamic> savedEnvelope({
  int page = 1,
  int last = 1,
  List<int> ids = const [1],
}) => {
  'data': ids.map((id) => savedPostJson(id)).toList(),
  'links': {
    'first': null,
    'last': null,
    'prev': null,
    'next': last > page
        ? 'https://travibeapp.com/api/v1/users/me/saved?page=${page + 1}'
        : null,
  },
  'meta': {
    'current_page': page,
    'last_page': last,
    'total': ids.length,
    'per_page': 15,
    'from': ids.isEmpty ? null : 1,
    'to': ids.isEmpty ? null : ids.length,
    'links': [],
    'path': 'https://travibeapp.com/api/v1/users/me/saved',
  },
};

class SavedRead {
  SavedRead(this.page);
  final int page;
  final result = Completer<PostsPageModel>();
}

class SavedWrite {
  SavedWrite(this.id, this.saved);
  final String id;
  final bool saved;
  final result = Completer<bool>();
}

class SavedRepo extends PostsRepo {
  final reads = <SavedRead>[];
  final writes = <SavedWrite>[];
  List<int> stored = [1];
  int last = 1;
  bool holdReads = false;
  bool holdWrites = false;
  Object? readError;
  Object? writeError;
  @override
  Future<PostsPageModel> getSavedPosts({int page = 1, int perPage = 15}) async {
    final call = SavedRead(page);
    reads.add(call);
    if (holdReads) return call.result.future;
    if (readError != null) throw readError!;
    return savedPage(List.of(stored), page: page, last: last);
  }

  @override
  Future<bool> setSaved(String postId, bool saved) async {
    final call = SavedWrite(postId, saved);
    writes.add(call);
    if (writeError != null) throw writeError!;
    final result = holdWrites ? await call.result.future : saved;
    if (result) {
      if (!stored.contains(int.parse(postId))) {
        stored.insert(0, int.parse(postId));
      }
    } else {
      stored.remove(int.parse(postId));
    }
    return result;
  }

  @override
  Future<PostsPageModel> getPosts({
    FeedType feed = FeedType.explore,
    String? cursor,
    int perPage = 15,
  }) async => PostsPageModel(
    pagination: fixtureMeta(current: fixturePage(cursor), last: 1),

    posts: [savedPost(1, saved: stored.contains(1))],
    currentPage: fixturePage(cursor),
    lastPage: 1,
    total: 1,
  );
}

Future<void> flushSaved() => Future<void>.delayed(Duration.zero);
