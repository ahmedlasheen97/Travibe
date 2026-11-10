import '../../helpers/cursor_fixtures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/comments/cubit/comments_cubit.dart';
import 'package:travibe/features/home/cubit/posts_cubit.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/home/data/posts_page_model.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/features/likes/cubit/likes_cubit.dart';
import 'package:travibe/features/likes/data/like_model.dart';
import '../home/posts_cubit_test.dart' as feeds;
import '../comments/fixtures.dart' as comments;
import 'fixtures.dart';

PostModel post(int id, {bool liked = false, int count = 2}) =>
    PostModel.fromJson({'id': id, 'is_liked': liked, 'likes_count': count});
PostsPageModel postsPage(int page, List<PostModel> posts) => PostsPageModel(
  pagination: fixtureMeta(current: page, last: 2),
  posts: posts,
  currentPage: page,
  lastPage: 2,
  total: 3,
);

void main() {
  late PendingLikesRepo repo;
  late LikesCubit likes;
  setUp(() {
    repo = PendingLikesRepo();
    likes = LikesCubit(repo: repo);
  });
  tearDown(() => likes.close());

  test(
    'Explore and Following share optimism, rollback and confirmation without reloading feeds',
    () async {
      final source = feeds.FakePostsRepo();
      final explore = PostsCubit(postsRepo: source, likes: likes);
      final following = PostsCubit(
        postsRepo: source,
        feed: FeedType.following,
        likes: likes,
      );
      addTearDown(explore.close);
      addTearDown(following.close);
      final first = explore.loadPosts();
      final second = following.loadPosts();
      for (final read in source.calls) {
        read.result.complete(postsPage(1, [post(10)]));
      }
      await Future.wait([first, second]);
      final request = explore.toggleLike(post(10));
      await flushLikes();
      for (final feed in [explore, following]) {
        final value = (feed.state as PostsLoaded).posts.single;
        expect(value.isLiked, isTrue);
        expect(value.likesCount, 3);
        expect((feed.state as PostsLoaded).hasMore, isTrue);
      }
      await following.toggleLike(post(10));
      expect(repo.writes, hasLength(1));
      repo.writes.single.result.completeError(ApiError(message: 'Failed'));
      await request;
      await flushLikes();
      expect((following.state as PostsLoaded).posts.single.isLiked, isFalse);
      final retry = following.toggleLike(post(10));
      repo.writes.last.result.complete(
        const LikeValue(isLiked: true, count: 6),
      );
      await retry;
      await flushLikes();
      expect((explore.state as PostsLoaded).posts.single.likesCount, 6);
      expect(source.calls, hasLength(2));
    },
  );
  test('stale refresh and pagination cannot undo a newer like', () async {
    final source = feeds.FakePostsRepo();
    final feed = PostsCubit(postsRepo: source, likes: likes);
    addTearDown(feed.close);
    final initial = feed.loadPosts();
    source.calls.last.result.complete(postsPage(1, [post(10)]));
    await initial;
    final more = feed.loadMore();
    final like = feed.toggleLike(post(10));
    repo.writes.last.result.complete(const LikeValue(isLiked: true, count: 3));
    await like;
    source.calls.last.result.complete(postsPage(2, [post(10), post(11)]));
    await more;
    expect((feed.state as PostsLoaded).posts.first.isLiked, isTrue);
    expect((feed.state as PostsLoaded).posts.map((p) => p.id), ['10', '11']);
    final refresh = feed.refresh();
    final unlike = feed.toggleLike(post(10));
    repo.writes.last.result.complete(const LikeValue(isLiked: false, count: 2));
    await unlike;
    source.calls.last.result.complete(
      postsPage(1, [post(10, liked: true, count: 3)]),
    );
    await refresh;
    expect((feed.state as PostsLoaded).posts.single.isLiked, isFalse);
    expect((feed.state as PostsLoaded).posts.single.likesCount, 2);
  });
  test(
    'comments and replies use one shared state and preserve hierarchy/pagination',
    () async {
      final source = comments.MemoryCommentsRepo()
        ..items[1] = comments.comment(1, replies: 1)
        ..items[2] = comments.comment(2, parentId: 1);
      final cubit = CommentsCubit(postId: 10, repo: source, likes: likes);
      addTearDown(cubit.close);
      await cubit.load();
      await cubit.load(parentId: 1);
      final rootLike = cubit.toggleLike(cubit.state.known[1]!);
      final replyLike = cubit.toggleLike(cubit.state.known[2]!);
      await flushLikes();
      expect(cubit.state.thread(null).comments.single.isLiked, isTrue);
      expect(cubit.state.thread(1).comments.single.isLiked, isTrue);
      expect(cubit.state.thread(1).comments.single.parentId, 1);
      expect(
        cubit.state.count,
        0,
      ); // A like never changes the post's comment count.
      expect(repo.writes.map((call) => call.target), [
        const LikeTarget.comment(10, 1),
        const LikeTarget.comment(10, 2),
      ]);
      repo.writes[0].result.complete(const LikeValue(isLiked: true, count: 3));
      repo.writes[1].result.complete(const LikeValue(isLiked: true, count: 7));
      await Future.wait([rootLike, replyLike]);
      await flushLikes();
      expect(cubit.state.known[2]!.likesCount, 7);
      cubit.remember(comments.comment(2, parentId: 1));
      expect(cubit.state.known[2]!.isLiked, isTrue);
      expect(cubit.state.known[2]!.likesCount, 7);
      expect(cubit.state.thread(1).nextCursor, isNull);
      expect(source.reads, hasLength(2));
    },
  );
  test(
    'reopening during a pending like and stale comment reads retain the confirmed state',
    () async {
      final source = comments.MemoryCommentsRepo()
        ..items[1] = comments.comment(1);
      final first = CommentsCubit(postId: 10, repo: source, likes: likes);
      await first.load();
      final request = first.toggleLike(first.state.known[1]!);
      await first.close();
      source.holdReads = true;
      final reopened = CommentsCubit(postId: 10, repo: source, likes: likes);
      addTearDown(reopened.close);
      final read = reopened.load();
      repo.writes.single.result.complete(
        const LikeValue(isLiked: true, count: 1),
      );
      await request;
      source.reads.last.result.complete(comments.page([comments.comment(1)]));
      await read;
      expect(reopened.state.known[1]!.isLiked, isTrue);
      expect(reopened.state.thread(null).comments.single.likesCount, 1);
    },
  );
  test(
    'comment rollback preserves content, replies and error details',
    () async {
      final source = comments.MemoryCommentsRepo()
        ..items[1] = comments.comment(1, replies: 3);
      final cubit = CommentsCubit(postId: 10, repo: source, likes: likes);
      addTearDown(cubit.close);
      await cubit.load();
      final original = cubit.state.known[1]!;
      final request = cubit.toggleLike(original);
      repo.writes.single.result.completeError(
        ApiError(message: 'Forbidden', statusCode: 403),
      );
      expect((await request)!.statusCode, 403);
      await flushLikes();
      expect(cubit.state.known[1]!.isLiked, isFalse);
      expect(cubit.state.known[1]!.likesCount, 0);
      expect(cubit.state.known[1]!.content, original.content);
      expect(cubit.state.known[1]!.repliesCount, original.repliesCount);
    },
  );
  test(
    'deleting and restoring a comment cannot resurrect its removed likes',
    () async {
      final source = comments.MemoryCommentsRepo()
        ..items[1] = comments.comment(1);
      final cubit = CommentsCubit(postId: 10, repo: source, likes: likes);
      addTearDown(cubit.close);
      await cubit.load();
      final request = cubit.toggleLike(cubit.state.known[1]!);
      repo.writes.single.result.complete(
        const LikeValue(isLiked: true, count: 1),
      );
      await request;
      await flushLikes();
      await cubit.delete(cubit.state.known[1]!);
      expect(likes.value(const LikeTarget.comment(10, 1))!.count, 0);
      await cubit.restore(1);
      expect(cubit.state.known[1]!.isLiked, isFalse);
      expect(cubit.state.known[1]!.likesCount, 0);
    },
  );
}
