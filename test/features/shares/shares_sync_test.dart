import '../../helpers/cursor_fixtures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/features/home/cubit/posts_cubit.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/home/data/posts_page_model.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/features/shares/cubit/shares_cubit.dart';
import 'package:travibe/features/shares/data/share_model.dart';
import '../home/posts_cubit_test.dart' as feeds;
import 'fixtures.dart';

PostModel post(int id, int count) => PostModel.fromJson({
  'id': id,
  'visibility': 'public',
  'shares_count': count,
  'is_liked': true,
  'likes_count': 4,
  'comments_count': 3,
});
PostsPageModel page(int number, List<PostModel> values) => PostsPageModel(
  pagination: fixtureMeta(current: number, last: 2),
  posts: values,
  currentPage: number,
  lastPage: 2,
  total: 3,
);

void main() {
  test(
    'Explore and Following synchronize shares without discarding posts or pagination',
    () async {
      final repo = MemorySharesRepo();
      final shares = SharesCubit(repo: repo);
      final source = feeds.FakePostsRepo();
      final explore = PostsCubit(postsRepo: source, shares: shares);
      final following = PostsCubit(
        postsRepo: source,
        feed: FeedType.following,
        shares: shares,
      );
      addTearDown(shares.close);
      addTearDown(explore.close);
      addTearDown(following.close);
      final first = explore.loadPosts();
      final second = following.loadPosts();
      for (final read in source.calls) {
        read.result.complete(page(1, [post(10, 2), post(11, 5)]));
      }
      await Future.wait([first, second]);
      await shares.inspect(10);
      await shares.create(10, const CreateShareRequest());
      await flushShares();
      for (final feed in [explore, following]) {
        final state = feed.state as PostsLoaded;
        expect(state.posts.first.sharesCount, 3);
        expect(state.posts.first.isLiked, isTrue);
        expect(state.posts.first.likesCount, 4);
        expect(state.posts.first.commentsCount, 3);
        expect(state.posts.last.sharesCount, 5);
        expect(state.hasMore, isTrue);
      }
      await shares.delete(10);
      await flushShares();
      expect((following.state as PostsLoaded).posts.first.sharesCount, 2);
      expect(source.calls, hasLength(2));
    },
  );
  test(
    'older pagination and refresh cannot replace newer confirmed counts',
    () async {
      final repo = MemorySharesRepo();
      final shares = SharesCubit(repo: repo);
      final source = feeds.FakePostsRepo();
      final feed = PostsCubit(postsRepo: source, shares: shares);
      addTearDown(shares.close);
      addTearDown(feed.close);
      final initial = feed.loadPosts();
      source.calls.last.result.complete(page(1, [post(10, 2)]));
      await initial;
      await shares.inspect(10);
      final more = feed.loadMore();
      await shares.create(10, const CreateShareRequest());
      source.calls.last.result.complete(page(2, [post(10, 2), post(11, 5)]));
      await more;
      expect((feed.state as PostsLoaded).posts.first.sharesCount, 3);
      expect((feed.state as PostsLoaded).posts, hasLength(2));
      final refresh = feed.refresh();
      await shares.delete(10);
      source.calls.last.result.complete(page(1, [post(10, 3)]));
      await refresh;
      expect((feed.state as PostsLoaded).posts.single.sharesCount, 2);
      final fresh = feed.refresh();
      source.calls.last.result.complete(page(1, [post(10, 7)]));
      await fresh;
      expect((feed.state as PostsLoaded).posts.single.sharesCount, 7);
    },
  );
  test(
    'missing shares_count in a resource cannot overwrite a known count',
    () async {
      final shares = SharesCubit(repo: MemorySharesRepo());
      shares.acceptCounts({10: 4}, requestRevision: 0);
      final source = feeds.FakePostsRepo();
      final feed = PostsCubit(postsRepo: source, shares: shares);
      addTearDown(shares.close);
      addTearDown(feed.close);
      final read = feed.loadPosts();
      source.calls.last.result.complete(
        page(1, [
          PostModel.fromJson({'id': 10}),
        ]),
      );
      await read;
      expect((feed.state as PostsLoaded).posts.single.sharesCount, 4);
    },
  );
}
