import '../../helpers/cursor_fixtures.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/features/comments/cubit/comments_cubit.dart';
import 'package:travibe/features/home/cubit/posts_cubit.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/home/data/posts_page_model.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'fixtures.dart';

class Posts extends PostsRepo {
  final calls = <Completer<PostsPageModel>>[];
  @override
  Future<PostsPageModel> getPosts({
    FeedType feed = FeedType.explore,
    String? cursor,
    int perPage = 15,
  }) {
    final call = Completer<PostsPageModel>();
    calls.add(call);
    return call.future;
  }
}

PostsPageModel posts(int count, {int current = 1}) => PostsPageModel(
  pagination: fixtureMeta(current: current, last: 2),

  posts: [
    PostModel.fromJson({'id': 10, 'comments_count': count}),
  ],
  currentPage: current,
  lastPage: 2,
  total: 2,
);
int count(PostsCubit cubit) =>
    (cubit.state as PostsLoaded).posts.single.commentsCount;
void main() {
  late Posts repo;
  late PostsCubit explore;
  late PostsCubit following;
  setUp(() {
    repo = Posts();
    explore = PostsCubit(postsRepo: repo);
    following = PostsCubit(postsRepo: repo, feed: FeedType.following);
  });
  tearDown(() async {
    await explore.close();
    await following.close();
  });
  Future<void> load(PostsCubit feed) async {
    final request = feed.loadPosts();
    repo.calls.last.complete(posts(2));
    await request;
  }

  test('one confirmed comment count updates both cached feed tabs', () async {
    await load(explore);
    await load(following);
    final comments = MemoryCommentsRepo()
      ..items.addAll({1: comment(1), 2: comment(2)});
    final cubit = CommentsCubit(
      postId: 10,
      repo: comments,
      initialCount: 2,
      onCountChanged: (value) {
        explore.setCommentsCount('10', value);
        following.setCommentsCount('10', value);
      },
    );
    addTearDown(cubit.close);
    await cubit.load();
    await cubit.create('New');
    expect(count(explore), 3);
    expect(count(following), 3);
    expect(repo.calls, hasLength(2));
  });
  test(
    'stale initial feed read cannot overwrite a confirmed comment count',
    () async {
      final request = explore.loadPosts();
      explore.setCommentsCount('10', 5);
      repo.calls.last.complete(posts(2));
      await request;
      expect(count(explore), 5);
    },
  );
  test('stale pagination cannot overwrite a confirmed count', () async {
    await load(explore);
    final more = explore.loadMore();
    explore.setCommentsCount('10', 5);
    repo.calls.last.complete(posts(2, current: 2));
    await more;
    expect(count(explore), 5);
  });
  test('a fresh feed refresh can adopt newer server counts', () async {
    await load(explore);
    explore.setCommentsCount('10', 5);
    final refresh = explore.refresh();
    repo.calls.last.complete(posts(6));
    await refresh;
    expect(count(explore), 6);
  });
  test(
    'hidden undo restores the latest confirmed count from its cached snapshot',
    () async {
      await load(explore);
      explore.setPostHidden('10', true);
      explore.setCommentsCount('10', 5);
      explore.setPostHidden('10', false);
      expect(count(explore), 5);
    },
  );
}
