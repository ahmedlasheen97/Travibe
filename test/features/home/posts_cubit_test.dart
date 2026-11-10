import '../../helpers/cursor_fixtures.dart';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/home/cubit/posts_cubit.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/home/data/posts_page_model.dart';
import 'package:travibe/features/home/data/posts_repo.dart';

class PendingPage {
  PendingPage(this.feed, this.page);
  final FeedType feed;
  final int page;
  final result = Completer<PostsPageModel>();
}

class FakePostsRepo extends PostsRepo {
  final calls = <PendingPage>[];

  @override
  Future<PostsPageModel> getPosts({
    FeedType feed = FeedType.explore,
    String? cursor,
    int perPage = 15,
  }) {
    final page = fixturePage(cursor);
    final call = PendingPage(feed, page);
    calls.add(call);
    return call.result.future;
  }
}

PostsPageModel page(int current, List<int> ids, {int last = 2}) =>
    PostsPageModel(
      pagination: fixtureMeta(current: current, last: last),

      posts: ids.map((id) => PostModel.fromJson({'id': id})).toList(),
      currentPage: current,
      lastPage: last,
      total: 3,
    );

List<String> ids(PostsCubit cubit) =>
    (cubit.state as PostsLoaded).posts.map((post) => post.id).toList();

void main() {
  late FakePostsRepo repo;
  late PostsCubit cubit;

  setUp(() {
    repo = FakePostsRepo();
    cubit = PostsCubit(postsRepo: repo);
  });
  tearDown(() => cubit.close());

  Future<void> initialLoad() async {
    final request = cubit.loadPosts();
    repo.calls.last.result.complete(page(1, [1, 2]));
    await request;
  }

  test('loads page one and coalesces duplicate initial requests', () async {
    final request = cubit.loadPosts();
    final duplicate = cubit.loadPosts();
    expect(cubit.state, isA<PostsLoading>());
    expect(repo.calls, hasLength(1));
    expect(repo.calls.single.feed, FeedType.explore);
    expect(repo.calls.single.page, 1);
    repo.calls.single.result.complete(page(1, [1, 2]));
    await Future.wait([request, duplicate]);
    expect(ids(cubit), ['1', '2']);
  });

  test('tabs load independently and retain their own data', () async {
    final following = PostsCubit(postsRepo: repo, feed: FeedType.following);
    addTearDown(following.close);
    final exploreRequest = cubit.loadPosts();
    final followingRequest = following.loadPosts();
    expect(repo.calls.map((call) => call.feed), [
      FeedType.explore,
      FeedType.following,
    ]);
    repo.calls[1].result.complete(page(1, [3], last: 1));
    await followingRequest;
    repo.calls[0].result.complete(page(1, [1]));
    await exploreRequest;
    expect(ids(cubit), ['1']);
    expect(ids(following), ['3']);
    expect((following.state as PostsLoaded).hasMore, isFalse);
  });

  test('empty success is loaded and stops pagination', () async {
    final request = cubit.loadPosts();
    repo.calls.single.result.complete(page(1, [], last: 1));
    await request;
    expect(ids(cubit), isEmpty);
    await cubit.loadMore();
    expect(repo.calls, hasLength(1));
  });

  test(
    'pagination deduplicates posts, prevents duplicate requests and stops',
    () async {
      await initialLoad();
      final request = cubit.loadMore();
      await cubit.loadMore();
      expect(repo.calls, hasLength(2));
      expect(repo.calls.last.page, 2);
      expect((cubit.state as PostsLoaded).isLoadingMore, isTrue);
      repo.calls.last.result.complete(page(2, [2, 3]));
      await request;
      expect(ids(cubit), ['1', '2', '3']);
      await cubit.loadMore();
      expect(repo.calls, hasLength(2));
    },
  );

  test('initial backend error retains message/status and can retry', () async {
    final error = ApiError(message: 'Unauthenticated', statusCode: 401);
    final request = cubit.loadPosts();
    repo.calls.last.result.completeError(error);
    await request;
    expect((cubit.state as PostsFailure).error, same(error));
    expect((cubit.state as PostsFailure).errorMessage, 'Unauthenticated');
    await initialLoad();
    expect(ids(cubit), ['1', '2']);
  });

  test(
    'pagination failure preserves posts and retries the same page explicitly',
    () async {
      await initialLoad();
      final error = ApiError(message: 'Try later', statusCode: 429);
      final request = cubit.loadMore();
      repo.calls.last.result.completeError(error);
      await request;
      expect(ids(cubit), ['1', '2']);
      expect((cubit.state as PostsLoaded).paginationError, same(error));
      await cubit.loadMore();
      expect(repo.calls, hasLength(2));
      final retry = cubit.loadMore(retry: true);
      expect(repo.calls.last.page, 2);
      repo.calls.last.result.complete(page(2, [3]));
      await retry;
      expect(ids(cubit), ['1', '2', '3']);
      expect((cubit.state as PostsLoaded).paginationError, isNull);
    },
  );

  test(
    'refresh retains visible posts, coalesces, and resets pagination',
    () async {
      await initialLoad();
      final refresh = cubit.refresh();
      final duplicate = cubit.refresh();
      expect(repo.calls, hasLength(2));
      expect((cubit.state as PostsLoaded).isRefreshing, isTrue);
      expect(ids(cubit), ['1', '2']);
      repo.calls.last.result.complete(page(1, [4]));
      await Future.wait([refresh, duplicate]);
      expect(ids(cubit), ['4']);
      final more = cubit.loadMore();
      expect(repo.calls.last.page, 2);
      repo.calls.last.result.complete(page(2, [5]));
      await more;
      expect(ids(cubit), ['4', '5']);
    },
  );

  test(
    'refresh failure preserves data, status and pagination position',
    () async {
      await initialLoad();
      final error = ApiError(message: 'Forbidden', statusCode: 403);
      final refresh = cubit.refresh();
      repo.calls.last.result.completeError(error);
      await refresh;
      expect(ids(cubit), ['1', '2']);
      expect((cubit.state as PostsLoaded).refreshError, same(error));
      expect((cubit.state as PostsLoaded).isRefreshing, isFalse);
      final more = cubit.loadMore();
      expect(repo.calls.last.page, 2);
      repo.calls.last.result.complete(page(2, [3]));
      await more;
    },
  );

  test(
    'late pagination cannot overwrite refresh or unlock newer pagination',
    () async {
      await initialLoad();
      final stale = cubit.loadMore();
      final staleCall = repo.calls.last;
      final refresh = cubit.refresh();
      repo.calls.last.result.complete(page(1, [4]));
      await refresh;
      final more = cubit.loadMore();
      final currentCall = repo.calls.last;
      staleCall.result.complete(page(2, [99]));
      await stale;
      expect(ids(cubit), ['4']);
      await cubit.loadMore();
      expect(repo.calls, hasLength(4));
      currentCall.result.complete(page(2, [5]));
      await more;
      expect(ids(cubit), ['4', '5']);
    },
  );

  test('completing a request after disposal does not emit', () async {
    final request = cubit.loadPosts();
    await cubit.close();
    repo.calls.single.result.complete(page(1, [1]));
    await request;
    expect(cubit.state, isA<PostsLoading>());
    await cubit.refresh();
    await cubit.loadMore();
    expect(repo.calls, hasLength(1));
  });
  test(
    'publication waits for an older load then requests a fresh first page',
    () async {
      final oldLoad = cubit.loadPosts();
      final publicationRefresh = cubit.refreshAfterPublication();
      expect(repo.calls, hasLength(1));
      repo.calls.first.result.complete(page(1, [1]));
      await oldLoad;
      await Future<void>.delayed(Duration.zero);
      expect(repo.calls, hasLength(2));
      expect(repo.calls.last.page, 1);
      repo.calls.last.result.complete(page(1, [42]));
      await publicationRefresh;
      expect(ids(cubit), ['42']);
    },
  );

  test(
    'publication refresh retains filters, concurrent counts and pagination',
    () async {
      PostsPageModel response() => PostsPageModel(
        pagination: fixtureMeta(current: 1, last: 2),

        posts: [
          PostModel.fromJson({
            'id': 1,
            'user_id': 7,
            'user': {'id': 7},
          }),
          PostModel.fromJson({
            'id': 2,
            'user_id': 8,
            'user': {'id': 8},
          }),
          PostModel.fromJson({
            'id': 42,
            'user_id': 9,
            'user': {'id': 9},
            'comments_count': 0,
          }),
        ],
        currentPage: 1,
        lastPage: 2,
        total: 4,
      );
      final initial = cubit.loadPosts();
      repo.calls.last.result.complete(response());
      await initial;
      cubit.setBlockedUsers({'7'});
      cubit.setPostHidden('2', true);
      final refreshing = cubit.refreshAfterPublication();
      await Future<void>.delayed(Duration.zero);
      cubit.setCommentsCount('42', 9);
      repo.calls.last.result.complete(response());
      await refreshing;
      expect(ids(cubit), ['42']);
      expect((cubit.state as PostsLoaded).posts.single.commentsCount, 9);
      final more = cubit.loadMore();
      expect(repo.calls.last.page, 2);
      repo.calls.last.result.complete(page(2, [43]));
      await more;
      expect(ids(cubit), ['42', '43']);
    },
  );
}
