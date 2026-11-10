import '../../helpers/cursor_fixtures.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/home/cubit/hidden_posts_cubit.dart';
import 'package:travibe/features/home/cubit/posts_cubit.dart';
import 'package:travibe/features/home/data/hidden_post_response.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/home/data/posts_page_model.dart';
import 'package:travibe/features/home/data/posts_repo.dart';

class HideCall {
  HideCall(this.id, this.hidden);
  final String id;
  final bool hidden;
  final result = Completer<HiddenPostResponse>();
}

class PageCall {
  PageCall(this.feed, this.page);
  final FeedType feed;
  final int page;
  final result = Completer<PostsPageModel>();
}

class HiddenRepo extends PostsRepo {
  final mutations = <HideCall>[];
  final pages = <PageCall>[];
  @override
  Future<HiddenPostResponse> setHidden(String postId, bool hidden) {
    final call = HideCall(postId, hidden);
    mutations.add(call);
    return call.result.future;
  }

  @override
  Future<PostsPageModel> getPosts({
    FeedType feed = FeedType.explore,
    String? cursor,
    int perPage = 15,
  }) {
    final page = fixturePage(cursor);
    final call = PageCall(feed, page);
    pages.add(call);
    return call.result.future;
  }
}

PostsPageModel page(int number, List<int> ids) => PostsPageModel(
  pagination: fixtureMeta(current: number, last: 3),

  posts: ids.map((id) => PostModel.fromJson({'id': id})).toList(),
  currentPage: number,
  lastPage: 3,
  total: 30,
);
List<String> ids(PostsCubit feed) =>
    (feed.state as PostsLoaded).posts.map((p) => p.id).toList();
void main() {
  late HiddenRepo repo;
  late PostsCubit explore;
  late PostsCubit following;
  late HiddenPostsCubit hidden;
  setUp(() {
    repo = HiddenRepo();
    explore = PostsCubit(postsRepo: repo);
    following = PostsCubit(postsRepo: repo, feed: FeedType.following);
    hidden = HiddenPostsCubit(repo: repo, feeds: [explore, following]);
  });
  tearDown(() async {
    await hidden.close();
    await explore.close();
    await following.close();
  });
  Future<void> loadFeeds() async {
    final a = explore.loadPosts();
    repo.pages.last.result.complete(page(1, [1, 7, 2]));
    await a;
    final b = following.loadPosts();
    repo.pages.last.result.complete(page(1, [7, 3]));
    await b;
  }

  Future<void> setHidden(bool value, {String id = '7'}) async {
    final request = hidden.setHidden(id, value);
    repo.mutations.last.result.complete(
      HiddenPostResponse(isHidden: value, message: 'Done'),
    );
    expect(await request, isNull);
  }

  test(
    'hide removes from both feeds only after confirmation without reloading',
    () async {
      await loadFeeds();
      final request = hidden.setHidden('7', true);
      expect(ids(explore), ['1', '7', '2']);
      expect(ids(following), ['7', '3']);
      expect(hidden.state.pending, contains('7'));
      repo.mutations.last.result.complete(
        const HiddenPostResponse(isHidden: true, message: 'Hidden'),
      );
      await request;
      expect(ids(explore), ['1', '2']);
      expect(ids(following), ['3']);
      expect(repo.pages, hasLength(2));
      expect(hidden.state.hidden, contains('7'));
    },
  );
  test(
    'confirmed undo restores original position independently in both feeds',
    () async {
      await loadFeeds();
      await setHidden(true);
      final undo = hidden.setHidden('7', false);
      expect(ids(explore), ['1', '2']);
      repo.mutations.last.result.complete(
        const HiddenPostResponse(isHidden: false, message: 'Unhidden'),
      );
      await undo;
      expect(ids(explore), ['1', '7', '2']);
      expect(ids(following), ['7', '3']);
      expect(repo.pages, hasLength(2));
      expect(hidden.state.hidden, isEmpty);
    },
  );
  test(
    'own-post 403 keeps both feeds unchanged and preserves backend error',
    () async {
      await loadFeeds();
      final request = hidden.setHidden('7', true);
      final error = ApiError(
        message: 'Cannot hide your own post',
        statusCode: 403,
      );
      repo.mutations.last.result.completeError(error);
      expect(await request, same(error));
      expect(ids(explore), ['1', '7', '2']);
      expect(ids(following), ['7', '3']);
      expect(hidden.state.pending, isEmpty);
      expect(hidden.state.hidden, isEmpty);
    },
  );
  test('failed unhide keeps the post hidden and permits retry', () async {
    await loadFeeds();
    await setHidden(true);
    final request = hidden.setHidden('7', false);
    final error = ApiError(message: 'Unavailable', statusCode: 503);
    repo.mutations.last.result.completeError(error);
    expect(await request, same(error));
    expect(ids(explore), ['1', '2']);
    expect(ids(following), ['3']);
    expect(hidden.state.hidden, contains('7'));
    await setHidden(false);
    expect(ids(explore), ['1', '7', '2']);
  });
  test(
    'duplicate and opposite requests are locked per post for hide and unhide',
    () async {
      await loadFeeds();
      for (final value in [true, false]) {
        final count = repo.mutations.length;
        final request = hidden.setHidden('7', value);
        await hidden.setHidden('7', value);
        await hidden.setHidden('7', !value);
        expect(repo.mutations, hasLength(count + 1));
        repo.mutations.last.result.complete(
          HiddenPostResponse(isHidden: value, message: 'Done'),
        );
        await request;
      }
    },
  );
  test('late pagination cannot resurrect a hidden post', () async {
    await loadFeeds();
    final more = explore.loadMore();
    final call = repo.pages.last;
    await setHidden(true);
    call.result.complete(page(2, [7, 4]));
    await more;
    expect(ids(explore), ['1', '2', '4']);
    expect(ids(following), ['3']);
  });
  test('pagination failure cannot restore a confirmed hide', () async {
    await loadFeeds();
    final more = explore.loadMore();
    final call = repo.pages.last;
    await setHidden(true);
    call.result.completeError(
      ApiError(message: 'Unavailable', statusCode: 503),
    );
    await more;
    expect(ids(explore), ['1', '2']);
    expect((explore.state as PostsLoaded).paginationError!.statusCode, 503);
  });
  test('undo during pagination survives the late page result', () async {
    await loadFeeds();
    await setHidden(true);
    final more = explore.loadMore();
    final call = repo.pages.last;
    await setHidden(false);
    call.result.complete(page(2, [4]));
    await more;
    expect(ids(explore), ['1', '7', '2', '4']);
  });
  test(
    'refresh response and failure both respect confirmed hidden state',
    () async {
      await loadFeeds();
      final refresh = explore.refresh();
      final call = repo.pages.last;
      await setHidden(true);
      call.result.complete(page(1, [1, 7, 4]));
      await refresh;
      expect(ids(explore), ['1', '4']);
      final failed = explore.refresh();
      repo.pages.last.result.completeError(ApiError(message: 'Offline'));
      await failed;
      expect(ids(explore), ['1', '4']);
    },
  );
  test(
    'multiple hides can be undone out of order without changing feed ordering',
    () async {
      await loadFeeds();
      await setHidden(true, id: '7');
      await setHidden(true, id: '1');
      await setHidden(false, id: '7');
      await setHidden(false, id: '1');
      expect(ids(explore), ['1', '7', '2']);
    },
  );
  test(
    'undo after refresh reloads only the feed with an expired snapshot',
    () async {
      await loadFeeds();
      await setHidden(true);
      final refresh = explore.refresh();
      repo.pages.last.result.complete(page(1, [1, 2]));
      await refresh;
      await setHidden(false);
      await Future<void>.delayed(Duration.zero);
      expect(repo.pages, hasLength(4));
      expect(repo.pages.last.feed, FeedType.explore);
      repo.pages.last.result.complete(page(1, [1, 7, 2]));
      await explore.pendingLoad;
      expect(ids(explore), ['1', '7', '2']);
      expect(ids(following), ['7', '3']);
    },
  );
  test(
    'late successful mutation after disposal cannot alter either feed',
    () async {
      await loadFeeds();
      final request = hidden.setHidden('7', true);
      await hidden.close();
      repo.mutations.last.result.complete(
        const HiddenPostResponse(isHidden: true, message: 'Done'),
      );
      await request;
      expect(ids(explore), ['1', '7', '2']);
      expect(ids(following), ['7', '3']);
    },
  );
  test(
    'undo after failed refresh restores cached order without a reload',
    () async {
      await loadFeeds();
      await setHidden(true);
      final refresh = explore.refresh();
      repo.pages.last.result.completeError(ApiError(message: 'Offline'));
      await refresh;
      await setHidden(false);
      expect(ids(explore), ['1', '7', '2']);
      expect(repo.pages, hasLength(3));
    },
  );
  test(
    'undo waits for an older initial feed request before fetching current membership',
    () async {
      final initial = explore.loadPosts();
      repo.pages.last.result.complete(page(1, [7]));
      await initial;
      final followingLoad = following.loadPosts();
      final old = repo.pages.last;
      await setHidden(true);
      await setHidden(false);
      old.result.complete(page(1, [3]));
      await followingLoad;
      await Future<void>.delayed(Duration.zero);
      expect(repo.pages, hasLength(3));
      expect(repo.pages.last.feed, FeedType.following);
      repo.pages.last.result.complete(page(1, [7, 3]));
      await following.pendingLoad;
      expect(ids(explore), ['7']);
      expect(ids(following), ['7', '3']);
    },
  );
  test(
    'different post requests keep independent locks and hidden state',
    () async {
      await loadFeeds();
      final a = hidden.setHidden('7', true);
      final b = hidden.setHidden('1', true);
      repo.mutations[1].result.complete(
        const HiddenPostResponse(isHidden: true, message: 'Done'),
      );
      await b;
      expect(hidden.state.pending, {'7'});
      repo.mutations[0].result.complete(
        const HiddenPostResponse(isHidden: true, message: 'Done'),
      );
      await a;
      expect(hidden.state.hidden, {'7', '1'});
      expect(ids(explore), ['2']);
      expect(ids(following), ['3']);
    },
  );
  test('a response that does not confirm hide cannot remove posts', () async {
    await loadFeeds();
    final request = hidden.setHidden('7', true);
    repo.mutations.last.result.complete(
      const HiddenPostResponse(isHidden: false, message: 'Unconfirmed'),
    );
    expect(await request, isA<ApiError>());
    expect(ids(explore), ['1', '7', '2']);
    expect(ids(following), ['7', '3']);
  });
}
