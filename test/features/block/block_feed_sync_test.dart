import '../../helpers/cursor_fixtures.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/home/cubit/hidden_posts_cubit.dart';
import 'package:travibe/features/home/cubit/posts_cubit.dart';
import 'package:travibe/features/home/data/hidden_post_response.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/home/data/posts_page_model.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'block_cubit_test.dart' as fixture;

class Posts extends PostsRepo {
  final requests = <Completer<PostsPageModel>>[];
  @override
  Future<PostsPageModel> getPosts({
    FeedType feed = FeedType.explore,
    String? cursor,
    int perPage = 15,
  }) {
    final request = Completer<PostsPageModel>();
    requests.add(request);
    return request.future;
  }

  @override
  Future<HiddenPostResponse> setHidden(String postId, bool hidden) async =>
      HiddenPostResponse(isHidden: hidden, message: 'Done');
}

PostsPageModel posts() => PostsPageModel(
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
      'id': 3,
      'user_id': 8,
      'user': {'id': 8},
      'original_post': {
        'id': 4,
        'user_id': 7,
        'user': {'id': 7},
      },
    }),
  ],
  currentPage: 1,
  lastPage: 2,
  total: 4,
);
List<String> ids(PostsCubit cubit) =>
    (cubit.state as PostsLoaded).posts.map((p) => p.id).toList();
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
  Future<void> load() async {
    for (final feed in [explore, following]) {
      final request = feed.loadPosts();
      repo.requests.last.complete(posts());
      await request;
    }
  }

  test(
    'confirmed block synchronizes both feeds including quoted authors',
    () async {
      await load();
      final follow = FollowCubit();
      final api = fixture.Repo();
      final block = BlockCubit(follow: follow, repo: api);
      final subscription = block.stream.listen((state) {
        explore.setBlockedUsers(state.blockedIds);
        following.setBlockedUsers(state.blockedIds);
      });
      addTearDown(() async {
        await subscription.cancel();
        await block.close();
        await follow.close();
      });
      final request = block.setBlocked('7', true);
      expect(ids(explore), ['1', '2', '3']);
      api.calls.last.result.complete(fixture.user('7', true));
      await request;
      await Future<void>.delayed(Duration.zero);
      expect(ids(explore), ['2']);
      expect(ids(following), ['2']);
      expect(repo.requests, hasLength(2));
      expect(follow.state.following['7'], isTrue);
    },
  );
  test('late page cannot restore blocked authors or quotes', () async {
    await load();
    final more = explore.loadMore();
    final request = repo.requests.last;
    explore.setBlockedUsers({'7'});
    request.complete(posts());
    await more;
    expect(ids(explore), ['2']);
  });
  test(
    'unblock revalidates membership instead of restoring obsolete posts',
    () async {
      await load();
      explore.setBlockedUsers({'7'});
      explore.setBlockedUsers({});
      expect(ids(explore), ['2']);
      final refresh = explore.refreshAfterBlockChange();
      await Future<void>.delayed(Duration.zero);
      repo.requests.last.complete(posts());
      await refresh;
      expect(ids(explore), ['1', '2', '3']);
    },
  );
  test('hidden-post undo cannot bypass an active author block', () async {
    await load();
    final hidden = HiddenPostsCubit(repo: repo, feeds: [explore, following]);
    addTearDown(hidden.close);
    await hidden.setHidden('1', true);
    explore.setBlockedUsers({'7'});
    following.setBlockedUsers({'7'});
    await hidden.setHidden('1', false);
    expect(ids(explore), ['2']);
    expect(ids(following), ['2']);
  });
}
