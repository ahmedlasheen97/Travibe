import '../../helpers/cursor_fixtures.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/home/cubit/posts_cubit.dart';
import 'package:travibe/features/home/cubit/post_activity_cubit.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/home/data/posts_page_model.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/features/likes/cubit/likes_cubit.dart';
import 'package:travibe/features/likes/data/like_model.dart';
import 'package:travibe/features/saved/cubit/saves_cubit.dart';
import 'package:travibe/features/saved/cubit/saved_posts_cubit.dart';
import '../saved/fixtures.dart';
import 'profile_posts_fixtures.dart';

class AuthorApi extends ApiService {
  String? path;
  Map<String, dynamic>? query;
  dynamic response;
  Object? error;
  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
    path = endpoint;
    query = queryParameters;
    if (error != null) throw error!;
    return response;
  }
}

class SamePostRepo extends AuthorPostsRepo {
  SamePostRepo() {
    stored = [201];
  }
  PostsPageModel resultPage() => PostsPageModel(
    pagination: fixtureMeta(current: 1, last: 1),

    posts: [authorPost(201, 23).copyWith(isSaved: stored.contains(201))],
    currentPage: 1,
    lastPage: 1,
    total: 1,
  );
  @override
  Future<PostsPageModel> getPosts({
    FeedType feed = FeedType.explore,
    String? cursor,
    int perPage = 15,
  }) async => resultPage();
  @override
  Future<PostsPageModel> getSavedPosts({
    int page = 1,
    int perPage = 15,
  }) async => stored.contains(201) ? resultPage() : authorPage(23, []);
  @override
  Future<PostsPageModel> getUserPosts({
    required int userId,
    String? cursor,
    int perPage = 15,
  }) async => resultPage();
}

void main() {
  late AuthorPostsRepo repo;
  late SavesCubit saves;
  late PostActivityCubit activity;
  late PostsCubit posts;
  late LikesCubit likes;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('author-session');
    repo = AuthorPostsRepo();
    saves = SavesCubit(repo: repo);
    activity = PostActivityCubit();
    likes = LikesCubit();
    posts = PostsCubit(
      userId: 23,
      postsRepo: repo,
      saves: saves,
      activity: activity,
      likes: likes,
    );
  });
  tearDown(() async {
    await posts.close();
    await saves.close();
    await activity.close();
    await likes.close();
  });
  test(
    'author GET sends verified user_id/cursor/per_page and maps optional viewer state',
    () async {
      final raw = authorPostJson(201, 23)
        ..remove('is_liked')
        ..remove('is_saved');
      final api = AuthorApi()
        ..response = {
          ...cursorEnvelope(next: 'older|opaque=='),
          'data': [raw],
        };
      final page = await PostsRepo(
        apiService: api,
      ).getUserPosts(userId: 23, cursor: 'next/+opaque==', perPage: 20);
      expect(api.path, 'posts');
      expect(api.query, {
        'user_id': 23,
        'cursor': 'next/+opaque==',
        'per_page': 20,
      });
      expect(page.posts.single.userId, '23');
      expect(page.posts.single.hasLikeState, false);
      expect(page.posts.single.hasSaveState, false);
      expect(page.hasMore, true);
      for (final args in [(0, null, 15), (23, '', 15), (23, null, 101)]) {
        await expectLater(
          PostsRepo(
            apiService: api,
          ).getUserPosts(userId: args.$1, cursor: args.$2, perPage: args.$3),
          throwsArgumentError,
        );
      }
    },
  );
  test(
    'author parser rejects malformed pages and other authors instead of filtering locally',
    () async {
      final api = AuthorApi();
      for (final response in [
        null,
        {'data': []},
        {
          ...savedEnvelope(),
          'data': [authorPostJson(1, 7)],
        },
        {...savedEnvelope(), 'meta': {}},
        {
          ...savedEnvelope(page: 2),
          'data': [authorPostJson(1, 23)],
        },
      ]) {
        api.response = response;
        await expectLater(
          PostsRepo(apiService: api).getUserPosts(userId: 23),
          throwsA(isA<ApiError>()),
        );
      }
    },
  );
  test(
    'author repository preserves auth errors and maps network exceptions',
    () async {
      final api = AuthorApi()
        ..error = ApiError(message: 'Expired', statusCode: 401);
      await expectLater(
        PostsRepo(apiService: api).getUserPosts(userId: 23),
        throwsA(same(api.error)),
      );
      api.error = DioException(
        requestOptions: RequestOptions(path: 'posts'),
        type: DioExceptionType.connectionError,
      );
      await expectLater(
        PostsRepo(apiService: api).getUserPosts(userId: 23),
        throwsA(isA<ApiError>()),
      );
    },
  );
  test(
    'author loads and pagination are independent of Explore and Saved',
    () async {
      final feed = PostsCubit(postsRepo: repo, saves: saves);
      final saved = SavedPostsCubit(saves: saves);
      await posts.loadPosts();
      await feed.loadPosts();
      await saved.load();
      expect(repo.authorReads.single.userId, 23);
      expect((posts.state as PostsLoaded).posts.single.id, '201');
      expect((feed.state as PostsLoaded).posts.single.id, '1');
      expect(saved.state.posts.single.id, '1');
      await feed.close();
      await saved.close();
    },
  );
  test(
    'author initial/pagination requests coalesce, deduplicate and stop',
    () async {
      repo.holdAuthors = true;
      final load = posts.loadPosts();
      final duplicate = posts.loadPosts();
      expect(repo.authorReads, hasLength(1));
      repo.authorReads[0].result.complete(authorPage(23, [201, 202], last: 2));
      await Future.wait([load, duplicate]);
      final more = posts.loadMore();
      await posts.loadMore();
      expect(repo.authorReads.last.page, 2);
      repo.authorReads[1].result.complete(
        authorPage(23, [202, 203], page: 2, last: 2),
      );
      await more;
      expect((posts.state as PostsLoaded).posts.map((p) => p.id), [
        '201',
        '202',
        '203',
      ]);
      expect((posts.state as PostsLoaded).hasMore, false);
    },
  );
  test('refresh rejects older pages; errors retry the same author', () async {
    repo.authorLast = 2;
    await posts.loadPosts();
    repo.holdAuthors = true;
    final older = posts.loadMore();
    final fresh = posts.refresh();
    repo.authorReads.last.result.complete(authorPage(23, [204]));
    await fresh;
    repo.authorReads[1].result.complete(
      authorPage(23, [201, 202], page: 2, last: 2),
    );
    await older;
    expect((posts.state as PostsLoaded).posts.single.id, '204');
    repo.holdAuthors = false;
    repo.authorError = ApiError(message: 'Offline');
    await posts.refresh();
    expect((posts.state as PostsLoaded).refreshError, isNotNull);
    repo.authorError = null;
    await posts.refresh();
    expect(repo.authorReads.last.userId, 23);
  });
  test('empty, failure and unauthorized refresh are distinct', () async {
    repo.authors[23] = [];
    await posts.loadPosts();
    expect((posts.state as PostsLoaded).posts, isEmpty);
    repo.authorError = ApiError(message: 'Expired', statusCode: 401);
    await posts.refresh();
    expect(posts.state, isA<PostsFailure>());
    repo.authorError = null;
    repo.authors[23] = [201];
    await posts.loadPosts();
    expect((posts.state as PostsLoaded).posts, hasLength(1));
  });
  test(
    'hidden posts stay in author lists; confirmed blocks still filter posts',
    () async {
      await posts.loadPosts();
      posts.setPostHidden('201', true);
      expect((posts.state as PostsLoaded).posts, hasLength(1));
      posts.setBlockedUsers({'23'});
      expect((posts.state as PostsLoaded).posts, isEmpty);
      posts.setBlockedUsers({});
      await posts.refreshAfterBlockChange();
      expect((posts.state as PostsLoaded).posts, hasLength(1));
    },
  );
  test('shared Like, Save and Comments reach the author cache', () async {
    await posts.loadPosts();
    final revision = likes.revision;
    likes.accept({
      const LikeTarget.post(201): const LikeValue(isLiked: true, count: 8),
    }, requestRevision: revision);
    activity.setCommentsCount('201', 9);
    await saves.toggle(authorPost(201, 23));
    await flushSaved();
    final post = (posts.state as PostsLoaded).posts.single;
    expect(post.isLiked, true);
    expect(post.likesCount, 8);
    expect(post.commentsCount, 9);
    expect(post.isSaved, true);
  });
  test(
    'comment snapshot cannot overwrite a newer mutation or fabricate missing counts',
    () async {
      final revision = activity.revision;
      activity.setCommentsCount('201', 9);
      activity.accept(
        [authorPost(201, 23)],
        requestRevision: revision,
        requestSession: activity.state.session,
      );
      expect(activity.state.comments['201'], 9);
      activity.accept(
        [
          PostModel.fromJson({'id': 201}),
        ],
        requestRevision: activity.revision,
        requestSession: activity.state.session,
      );
      expect(activity.state.comments['201'], 9);
    },
  );
  test(
    'session change invalidates pending author reads without reusing the old owner ID',
    () async {
      repo.holdAuthors = true;
      final pending = posts.loadPosts();
      await PreferencesManager().saveToken('new-session');
      await flushSaved();
      expect(posts.state, isA<PostsInitial>());
      expect(repo.authorReads, hasLength(1));
      repo.authorReads.single.result.complete(authorPage(23, [201]));
      await pending;
      expect(posts.state, isA<PostsInitial>());
    },
  );
  test(
    'same post shares confirmed interactions across Profile, both feeds and Saved',
    () async {
      final repo = SamePostRepo();
      final sharedSaves = SavesCubit(repo: repo);
      final saved = SavedPostsCubit(
        saves: sharedSaves,
        repo: repo,
        activity: activity,
        likes: likes,
      );
      final views = [
        for (final author in [null, 23])
          PostsCubit(
            userId: author,
            postsRepo: repo,
            likes: likes,
            saves: sharedSaves,
            activity: activity,
          ),
        PostsCubit(
          feed: FeedType.following,
          postsRepo: repo,
          likes: likes,
          saves: sharedSaves,
          activity: activity,
        ),
      ];
      for (final view in views) {
        await view.loadPosts();
      }
      await saved.load();
      activity.setCommentsCount('201', 10);
      likes.accept({
        const LikeTarget.post(201): const LikeValue(isLiked: true, count: 8),
      }, requestRevision: likes.revision);
      await sharedSaves.toggle(authorPost(201, 23));
      await flushSaved();
      for (final view in views) {
        final post = (view.state as PostsLoaded).posts.single;
        expect(post.commentsCount, 10);
        expect(post.likesCount, 8);
        expect(post.isSaved, false);
        await view.close();
      }
      expect(saved.state.posts, isEmpty);
      await saved.close();
      await sharedSaves.close();
    },
  );

  test('disposed author loader cannot publish old interactions', () async {
    repo.holdAuthors = true;
    final pending = posts.loadPosts();
    await posts.close();
    repo.authorReads.single.result.complete(authorPage(23, [201]));
    await pending;
    expect(activity.state.comments, isEmpty);
  });
}
