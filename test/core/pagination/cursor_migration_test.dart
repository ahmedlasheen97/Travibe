import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/cubit/cursor_list_cubit.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/core/models/cursor_pagination.dart';
import 'package:travibe/features/home/cubit/posts_cubit.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/features/comments/cubit/comments_cubit.dart';
import 'package:travibe/features/comments/data/comments_repo.dart';
import 'package:travibe/features/likes/cubit/likes_users_cubit.dart';
import 'package:travibe/features/likes/data/like_model.dart';
import 'package:travibe/features/likes/data/likes_repo.dart';
import 'package:travibe/features/notifications/data/notifications_repo.dart';
import 'package:travibe/features/notifications/cubit/notifications_cubit.dart';
import '../../features/comments/fixtures.dart' as comments;
import '../../helpers/cursor_fixtures.dart';

const opaque = 'eyJpZCI6N30=+/ cursor';

class Read {
  Read(this.path, this.query);
  final String path;
  final Map<String, dynamic> query;
  final result = Completer<dynamic>();
}

class CursorApi extends ApiService {
  final reads = <Read>[];
  bool hold = false;
  Object? error;
  String? next = opaque;
  List<dynamic>? data;
  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final read = Read(endpoint, Map.of(queryParameters ?? {}));
    reads.add(read);
    // Actual Laravel regression: these endpoints reject offset pagination.
    if (read.query.containsKey('page')) {
      throw ApiError(
        message:
            'Offset pagination is not supported. Use the cursor from meta.next_cursor.',
        statusCode: 422,
      );
    }
    if (hold) return read.result.future;
    if (error != null) throw error!;
    return envelope(endpoint, data: data, next: next);
  }
}

Map<String, dynamic> envelope(
  String path, {
  List<dynamic>? data,
  String? next,
  String? prev,
}) {
  final items =
      data ??
      (path.endsWith('/comments')
          ? [
              {
                ...comments.commentJson(1),
                'post_id': int.parse(path.split('/')[1]),
              },
            ]
          : path.endsWith('/likes')
          ? [
              {'id': 3, 'name': 'Sam'},
            ]
          : path == 'notifications'
          ? [
              {
                'id': 'notification-1',
                'read_at': null,
                'data': {'post_id': 1},
              },
            ]
          : [
              {'id': 1, 'user_id': 23},
            ]);
  return {
    ...cursorEnvelope(data: items, next: next, prev: prev),
    'meta': {
      ...cursorEnvelope(next: next, prev: prev)['meta'] as Map,
      'path': 'https://travibeapp.com/api/v1/$path',
    },
  };
}

void main() {
  final preferences = PreferencesManager();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.saveToken('cursor-account-A');
  });
  tearDown(() => preferences.clear());

  final endpoints = [
    'feed/following',
    'feed/explore',
    'posts',
    'posts/1/likes',
    'posts/1/comments/2/likes',
    'stories/1/likes',
    'posts/1/comments',
    'notifications',
  ];
  for (final path in endpoints) {
    test(
      '$path first and next reads match cursor-only Laravel contract (422 regression)',
      () async {
        final api = CursorApi();
        final posts = PostsRepo(apiService: api);
        final likes = LikesRepo(apiService: api);
        Future<dynamic> read(String? cursor) => switch (path) {
          'feed/following' => posts.getPosts(
            feed: FeedType.following,
            cursor: cursor,
          ),
          'feed/explore' => posts.getPosts(cursor: cursor),
          'posts' => posts.getUserPosts(userId: 23, cursor: cursor),
          'posts/1/likes' => likes.list(
            const LikeTarget.post(1),
            cursor: cursor,
          ),
          'posts/1/comments/2/likes' => likes.list(
            const LikeTarget.comment(1, 2),
            cursor: cursor,
          ),
          'stories/1/likes' => likes.listStory(1, cursor: cursor),
          'posts/1/comments' => CommentsRepo(
            apiService: api,
          ).list(1, cursor: cursor),
          _ => NotificationsRepo(apiService: api).list(cursor: cursor),
        };
        final dynamic first = await read(null);
        expect(first.pagination.nextCursor, opaque);
        expect(api.reads.single.path, path);
        expect(api.reads.single.query, {
          'per_page': 15,
          if (path == 'posts') 'user_id': 23,
        });
        api.next = null;
        final dynamic last = await read(first.pagination.nextCursor as String);
        expect(last.hasMore, false);
        expect(api.reads.last.query, {
          'per_page': 15,
          'cursor': opaque,
          if (path == 'posts') 'user_id': 23,
        });
      },
    );
    test('$path empty data and null next cursor are valid', () async {
      final api = CursorApi()
        ..data = []
        ..next = null;
      // Exercise the shared parser against every endpoint's response path.
      final page = CursorPage<dynamic>.fromJson(
        await api.get(path, queryParameters: cursorQuery()),
        (item) => item,
      );
      expect(page.items, isEmpty);
      expect(page.hasMore, false);
    });
  }
  test(
    'unscoped GET posts omits user_id as well as offset parameters',
    () async {
      final api = CursorApi();
      final result = await PostsRepo(apiService: api).listPosts();
      expect(api.reads.single.query, {'per_page': 15});
      expect(result.pagination!.nextCursor, opaque);
    },
  );
  test(
    'meta preserves opaque cursors and previous cursor without offset totals',
    () {
      final meta = CursorPaginationMeta.fromJson(
        cursorEnvelope(next: opaque, prev: 'previous token')['meta'],
      );
      expect(meta.nextCursor, opaque);
      expect(meta.prevCursor, 'previous token');
      expect(cursorQuery(cursor: meta.prevCursor), {
        'per_page': 15,
        'cursor': 'previous token',
      });
    },
  );
  for (final meta in [
    null,
    {},
    {'current_page': 1, 'last_page': 2, 'total': 30},
    {...cursorEnvelope()['meta'] as Map, 'next_cursor': 1},
    {...cursorEnvelope()['meta'] as Map, 'next_cursor': ''},
    {...cursorEnvelope()['meta'] as Map, 'per_page': 0},
  ]) {
    test(
      'invalid or offset-only meta $meta is not silently treated as exhausted',
      () {
        expect(
          () => CursorPaginationMeta.fromJson(meta),
          throwsA(isA<ApiError>()),
        );
      },
    );
  }
  test('cursor progress halts direct repetition and longer cycles', () {
    final progress = CursorProgress();
    CursorPaginationMeta meta(String? next) =>
        CursorPaginationMeta(path: '/posts', perPage: 15, nextCursor: next);
    progress.accept(meta('a'));
    progress.accept(meta('a'), requestedCursor: 'a');
    expect(progress.hasMore, false);
    progress.accept(meta('a'));
    progress.accept(meta('b'), requestedCursor: 'a');
    progress.accept(meta('a'), requestedCursor: 'b');
    expect(progress.hasMore, false);
    progress.accept(meta('a')); // a successful refresh starts a new traversal
    expect(progress.nextCursor, 'a');
  });
  test(
    'notifications pagination merges IDs while preserving all notification fields',
    () async {
      final api = CursorApi();
      final cubit = NotificationsCubit(
        repo: NotificationsRepo(apiService: api),
      );
      addTearDown(cubit.close);
      await cubit.load();
      api.data = [
        {
          'id': 'notification-1',
          'read_at': 'server timestamp',
          'data': {'post_id': 1},
        },
        {'id': 'notification-2', 'read_at': null},
      ];
      api.next = null;
      await cubit.more();
      expect(cubit.state.items.map((i) => i['id']), [
        'notification-1',
        'notification-2',
      ]);
      expect(cubit.state.items.first['read_at'], 'server timestamp');
      expect(cubit.state.items.first['data'], {'post_id': 1});
      expect(cubit.state.hasMore, false);
      await cubit.more();
      expect(api.reads, hasLength(2));
    },
  );
  test(
    'notifications coalesce reads; failed continuation retries the exact cursor',
    () async {
      final api = CursorApi()..hold = true;
      final cubit = NotificationsCubit(
        repo: NotificationsRepo(apiService: api),
      );
      addTearDown(cubit.close);
      final first = cubit.load();
      final duplicate = cubit.load();
      expect(api.reads, hasLength(1));
      api.reads.single.result.complete(envelope('notifications', next: opaque));
      await Future.wait([first, duplicate]);
      final more = cubit.more();
      await cubit.more();
      expect(api.reads, hasLength(2));
      api.reads.last.result.completeError(ApiError(message: 'Offline'));
      await more;
      expect(cubit.state.items, hasLength(1));
      expect(cubit.state.paginationError, isNotNull);
      expect(cubit.state.loadingMore, false);
      await cubit.more();
      expect(api.reads, hasLength(2));
      api.hold = false;
      api.next = null;
      await cubit.more(retry: true);
      expect(api.reads.last.query, {'per_page': 15, 'cursor': opaque});
      expect(cubit.state.paginationError, isNull);
    },
  );
  test(
    'refresh discards old continuation and resets the request cursor',
    () async {
      final api = CursorApi();
      final cubit = NotificationsCubit(
        repo: NotificationsRepo(apiService: api),
      );
      addTearDown(cubit.close);
      await cubit.load();
      api.hold = true;
      final more = cubit.more();
      final old = api.reads.last;
      final refresh = cubit.refresh();
      expect(api.reads.last.query, {'per_page': 15});
      api.reads.last.result.complete(
        envelope(
          'notifications',
          data: [
            {'id': 'fresh'},
          ],
        ),
      );
      await refresh;
      old.result.complete(
        envelope(
          'notifications',
          data: [
            {'id': 'stale'},
          ],
          next: opaque,
        ),
      );
      await more;
      expect(cubit.state.items.single['id'], 'fresh');
      expect(cubit.state.hasMore, false);
    },
  );
  test(
    'empty continuation with advancing cursor is safe; repeated cursor terminates',
    () async {
      final api = CursorApi();
      final cubit = NotificationsCubit(
        repo: NotificationsRepo(apiService: api),
      );
      addTearDown(cubit.close);
      await cubit.load();
      api.data = [];
      api.next = 'next empty';
      await cubit.more();
      expect(cubit.state.items, hasLength(1));
      expect(cubit.nextCursor, 'next empty');
      await cubit.more();
      expect(cubit.state.hasMore, false);
      await cubit.more();
      expect(api.reads, hasLength(3));
    },
  );
  test(
    'session switch clears notification cursor and ignores old responses',
    () async {
      final api = CursorApi()..hold = true;
      final cubit = NotificationsCubit(
        repo: NotificationsRepo(apiService: api),
      );
      addTearDown(cubit.close);
      final old = cubit.load();
      await preferences.saveToken('cursor-account-B');
      expect(cubit.state.items, isEmpty);
      api.reads.single.result.complete(envelope('notifications', next: opaque));
      await old;
      expect(cubit.state.status, CursorListStatus.initial);
      api.hold = false;
      api.next = null;
      await cubit.load();
      expect(api.reads.last.query, {'per_page': 15});
    },
  );
  test(
    'following and explore retain independent opaque cursors under rapid switching',
    () async {
      final api = CursorApi()..hold = true;
      final repo = PostsRepo(apiService: api);
      final following = PostsCubit(postsRepo: repo, feed: FeedType.following);
      final explore = PostsCubit(postsRepo: repo);
      addTearDown(following.close);
      addTearDown(explore.close);
      final a = following.loadPosts();
      final b = explore.loadPosts();
      api.reads[1].result.complete(
        envelope('feed/explore', next: 'explore-next'),
      );
      api.reads[0].result.complete(
        envelope('feed/following', next: 'following-next'),
      );
      await Future.wait([a, b]);
      final c = following.loadMore();
      final d = explore.loadMore();
      expect(api.reads[2].query['cursor'], 'following-next');
      expect(api.reads[3].query['cursor'], 'explore-next');
      api.reads[3].result.complete(envelope('feed/explore'));
      api.reads[2].result.complete(envelope('feed/following'));
      await Future.wait([c, d]);
    },
  );
  test(
    'standalone feed session reset rejects old author data and clears cursor',
    () async {
      final api = CursorApi();
      final cubit = PostsCubit(postsRepo: PostsRepo(apiService: api));
      addTearDown(cubit.close);
      await cubit.loadPosts();
      api.hold = true;
      final more = cubit.loadMore();
      await preferences.saveToken('cursor-account-B');
      api.reads.last.result.complete(envelope('feed/explore', next: opaque));
      await more;
      expect(cubit.state, isA<PostsInitial>());
      api.hold = false;
      await cubit.loadPosts();
      expect(api.reads.last.query, {'per_page': 15});
    },
  );
  test('author cursors remain isolated between profiles', () async {
    final api = CursorApi()..hold = true;
    final repo = PostsRepo(apiService: api);
    final one = PostsCubit(postsRepo: repo, userId: 23);
    final two = PostsCubit(postsRepo: repo, userId: 42);
    addTearDown(one.close);
    addTearDown(two.close);
    final a = one.loadPosts();
    final b = two.loadPosts();
    api.reads[1].result.complete(
      envelope(
        'posts',
        data: [
          {'id': 9, 'user_id': 42},
        ],
        next: 'author-42',
      ),
    );
    api.reads[0].result.complete(envelope('posts', next: 'author-23'));
    await Future.wait([a, b]);
    final c = one.loadMore();
    final d = two.loadMore();
    expect(api.reads[2].query, {
      'user_id': 23,
      'per_page': 15,
      'cursor': 'author-23',
    });
    expect(api.reads[3].query, {
      'user_id': 42,
      'per_page': 15,
      'cursor': 'author-42',
    });
    api.reads[2].result.complete(envelope('posts'));
    api.reads[3].result.complete(
      envelope(
        'posts',
        data: [
          {'id': 9, 'user_id': 42},
        ],
      ),
    );
    await Future.wait([c, d]);
  });
  test(
    'comments/replies keep parent filters and independent cursor state',
    () async {
      final api = CursorApi();
      final cubit = CommentsCubit(
        postId: 10,
        repo: CommentsRepo(apiService: api),
      );
      addTearDown(cubit.close);
      await cubit.load();
      api.data = [comments.commentJson(2, parentId: 1)];
      api.next = 'reply-next';
      await cubit.load(parentId: 1);
      expect(api.reads.last.query, {'per_page': 15, 'parent_id': '1'});
      api.next = null;
      await cubit.more(parentId: 1);
      expect(api.reads.last.query, {
        'per_page': 15,
        'parent_id': '1',
        'cursor': 'reply-next',
      });
      expect(cubit.state.thread(null).nextCursor, opaque);
      expect(cubit.state.thread(1).nextCursor, isNull);
    },
  );
  test('comments session change ignores a pending root/reply read', () async {
    final api = CursorApi()..hold = true;
    final cubit = CommentsCubit(
      postId: 10,
      repo: CommentsRepo(apiService: api),
    );
    addTearDown(cubit.close);
    final old = cubit.load();
    await preferences.saveToken('cursor-account-B');
    api.reads.single.result.complete(
      envelope('posts/10/comments', next: opaque),
    );
    await old;
    expect(cubit.state.threads, isEmpty);
    api.hold = false;
    await cubit.load();
    expect(api.reads.last.query, {'per_page': 15});
  });
  for (final story in [false, true]) {
    test(
      '${story ? 'Story' : 'Post'} likes use session-safe cursor list state',
      () async {
        final api = CursorApi();
        final repo = LikesRepo(apiService: api);
        final cubit = story
            ? LikesUsersCubit.story(storyId: 1, repo: repo)
            : LikesUsersCubit(target: const LikeTarget.post(1), repo: repo);
        addTearDown(cubit.close);
        await cubit.load();
        api.next = null;
        await cubit.more();
        expect(api.reads.last.query['cursor'], opaque);
        expect(cubit.state.items, hasLength(1));
        await preferences.clear();
        expect(cubit.state.items, isEmpty);
      },
    );
  }
}
