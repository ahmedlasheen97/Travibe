import 'package:dio/dio.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/home/cubit/posts_cubit.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/features/saved/cubit/saves_cubit.dart';
import 'package:travibe/features/saved/cubit/saved_posts_cubit.dart';
import 'fixtures.dart';

class SavedApi extends ApiService {
  String? method;
  String? path;
  Map<String, dynamic>? body;
  Map<String, dynamic>? query;
  dynamic response;
  Object? error;
  dynamic _result(String verb, String endpoint) {
    method = verb;
    path = endpoint;
    if (error != null) throw error!;
    return response;
  }

  @override
  Future<dynamic> post(String endpoint, Map<String, dynamic> data) async {
    body = data;
    return _result('POST', endpoint);
  }

  @override
  Future<dynamic> delete(String endpoint) async => _result('DELETE', endpoint);
  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
    query = queryParameters;
    return _result('GET', endpoint);
  }
}

class ConfirmedBlocks extends BlockCubit {
  ConfirmedBlocks({required super.follow});
  void confirm(bool blocked) => emit(BlockState(blocked: {'9': blocked}));
}

void main() {
  late PreferencesManager preferences;
  late SavedRepo repo;
  late SavesCubit saves;
  late SavedPostsCubit list;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = PreferencesManager();
    await preferences.init();
    await preferences.saveToken('account-a');
    repo = SavedRepo();
    saves = SavesCubit(repo: repo, preferences: preferences);
    list = SavedPostsCubit(saves: saves);
  });
  tearDown(() async {
    await list.close();
    await saves.close();
  });

  test(
    'Save/Unsave use documented methods and top-level confirmation',
    () async {
      final api = SavedApi()..response = {'is_saved': true, 'message': 'Saved'};
      final real = PostsRepo(apiService: api);
      expect(await real.setSaved('7', true), true);
      expect(api.method, 'POST');
      expect(api.path, 'posts/7/save');
      expect(api.body, isEmpty);
      api.response = {'is_saved': false, 'message': 'Unsaved'};
      expect(await real.setSaved('7', false), false);
      expect(api.method, 'DELETE');
      expect(api.path, 'posts/7/save');
      for (final bad in [
        null,
        {
          'data': {'is_saved': true},
        },
        {'is_saved': 'true'},
        {'is_saved': false},
      ]) {
        api.response = bad;
        await expectLater(real.setSaved('7', true), throwsA(isA<ApiError>()));
      }
      await expectLater(real.setSaved('invalid', true), throwsArgumentError);
    },
  );
  test(
    'Saved list maps documented envelope, pagination and optional viewer state',
    () async {
      final api = SavedApi()..response = savedEnvelope(page: 2, last: 3);
      final result = await PostsRepo(
        apiService: api,
      ).getSavedPosts(page: 2, perPage: 20);
      expect(api.path, 'users/me/saved');
      expect(api.query, {'page': 2, 'per_page': 20});
      expect(result.currentPage, 2);
      expect(result.hasMore, true);
      expect(result.posts.single.isSaved, true);
      final raw = savedPostJson(1)..remove('is_saved');
      api.response = {
        ...savedEnvelope(),
        'data': [raw],
      };
      expect(
        (await PostsRepo(apiService: api).getSavedPosts()).posts.single.isSaved,
        true,
      );
    },
  );
  test(
    'malformed saved responses do not masquerade as empty success',
    () async {
      final api = SavedApi();
      final real = PostsRepo(apiService: api);
      for (final value in [
        null,
        {'data': []},
        {...savedEnvelope(), 'meta': {}},
        {
          ...savedEnvelope(),
          'data': [
            {'id': 1},
          ],
        },
        {
          ...savedEnvelope(),
          'data': [savedPostJson(1, saved: false)],
        },
        savedEnvelope(page: 2),
      ]) {
        api.response = value;
        await expectLater(real.getSavedPosts(), throwsA(isA<ApiError>()));
      }
      await expectLater(real.getSavedPosts(perPage: 101), throwsArgumentError);
    },
  );
  test('repository preserves HTTP errors and maps network failure', () async {
    final api = SavedApi();
    final real = PostsRepo(apiService: api);
    for (final code in [401, 403, 404, 422]) {
      final error = ApiError(message: 'Backend message', statusCode: code);
      api.error = error;
      await expectLater(real.setSaved('1', true), throwsA(same(error)));
      await expectLater(real.getSavedPosts(), throwsA(same(error)));
    }
    api.error = DioException(
      requestOptions: RequestOptions(path: 'users/me/saved'),
      type: DioExceptionType.connectionError,
    );
    await expectLater(real.getSavedPosts(), throwsA(isA<ApiError>()));
  });
  test(
    'confirmed save and unsave only; duplicate mutations prevented',
    () async {
      repo.holdWrites = true;
      final post = savedPost(1, saved: false);
      final first = saves.toggle(post);
      expect(saves.state.pending, contains('1'));
      expect(saves.apply(post).isSaved, false);
      await saves.toggle(post);
      expect(repo.writes, hasLength(1));
      repo.writes.single.result.complete(true);
      expect(await first, isNull);
      expect(saves.apply(post).isSaved, true);
      expect(saves.state.pending, isEmpty);
      final unsave = saves.toggle(post);
      expect(repo.writes.last.saved, false);
      expect(saves.apply(post).isSaved, true);
      repo.writes.last.result.complete(false);
      await unsave;
      expect(saves.apply(post).isSaved, false);
    },
  );
  test(
    'save and unsave failures preserve confirmed state and permit retry',
    () async {
      for (final saved in [false, true]) {
        for (final code in [401, 403, 404, 422, null]) {
          final post = savedPost(2, saved: saved);
          final error = ApiError(message: 'Could not update', statusCode: code);
          repo.writeError = error;
          expect(await saves.toggle(post), same(error));
          expect(saves.apply(post).isSaved, saved);
          expect(saves.state.pending, isEmpty);
        }
      }
      repo.writeError = null;
      expect(await saves.toggle(savedPost(2, saved: false)), isNull);
    },
  );
  test('unknown viewer state cannot choose a toggle direction', () async {
    final error = await saves.toggle(PostModel.fromJson({'id': 1}));
    expect(error, isA<ApiError>());
    expect(repo.writes, isEmpty);
  });
  test(
    'initial load is coalesced, paginates, deduplicates and stops',
    () async {
      repo.holdReads = true;
      final first = list.load();
      final duplicate = list.load();
      expect(repo.reads, hasLength(1));
      expect(list.state.status, SavedPostsStatus.loading);
      repo.reads[0].result.complete(savedPage([1, 2], last: 2));
      await Future.wait([first, duplicate]);
      final more = list.loadMore();
      await list.loadMore();
      expect(repo.reads.last.page, 2);
      expect(repo.reads, hasLength(2));
      repo.reads[1].result.complete(savedPage([2, 3], page: 2, last: 2));
      await more;
      expect(list.state.posts.map((p) => p.id), ['1', '2', '3']);
      expect(list.state.hasMore, false);
      await list.loadMore();
      expect(repo.reads, hasLength(2));
    },
  );
  test(
    'empty, error and retry are distinct; refresh failure retains own data',
    () async {
      repo.readError = ApiError(message: 'Offline');
      await list.load();
      expect(list.state.status, SavedPostsStatus.failure);
      repo.readError = null;
      repo.stored = [];
      await list.load();
      expect(list.state.status, SavedPostsStatus.loaded);
      expect(list.state.posts, isEmpty);
      repo.stored = [1];
      await list.refresh();
      expect(list.state.posts, hasLength(1));
      repo.readError = ApiError(message: 'Offline');
      await list.refresh();
      expect(list.state.posts, hasLength(1));
      expect(list.state.error!.message, 'Offline');
      repo.readError = ApiError(message: 'Expired', statusCode: 401);
      await list.refresh();
      expect(list.state.posts, isEmpty);
      expect(list.state.status, SavedPostsStatus.failure);
    },
  );
  test('pagination error is retried explicitly', () async {
    repo.last = 2;
    await list.load();
    repo.readError = ApiError(message: 'Offline');
    await list.loadMore();
    expect(list.state.paginationError, isNotNull);
    final count = repo.reads.length;
    await list.loadMore();
    expect(repo.reads.length, count);
    repo.readError = null;
    await list.loadMore(retry: true);
    expect(list.state.paginationError, isNull);
  });
  test('refresh supersedes old pagination and replaces membership', () async {
    repo.last = 2;
    await list.load();
    repo.holdReads = true;
    final old = list.loadMore();
    final fresh = list.refresh();
    repo.reads.last.result.complete(savedPage([3]));
    await fresh;
    repo.reads[1].result.complete(savedPage([1, 2], page: 2, last: 2));
    await old;
    expect(list.state.posts.map((p) => p.id), ['3']);
  });
  test(
    'unsave removes from Saved and updates both feeds without stale resurrection',
    () async {
      final explore = PostsCubit(postsRepo: repo, saves: saves);
      final following = PostsCubit(
        postsRepo: repo,
        saves: saves,
        feed: FeedType.following,
      );
      await explore.loadPosts();
      await following.loadPosts();
      repo.last = 2;
      await list.load();
      repo.holdReads = true;
      final stale = list.loadMore();
      await saves.toggle(savedPost(1));
      await flushSaved();
      expect(list.state.posts, isEmpty);
      expect((explore.state as PostsLoaded).posts.single.isSaved, false);
      expect((following.state as PostsLoaded).posts.single.isSaved, false);
      repo.reads[1].result.complete(savedPage([1, 2], page: 2, last: 2));
      await stale;
      expect(list.state.posts, isEmpty);
      repo.reads.last.result.complete(savedPage([]));
      await flushSaved();
      await explore.close();
      await following.close();
    },
  );
  test(
    'feed save fetches Saved membership rather than inserting feed snapshots',
    () async {
      repo.stored = [];
      await list.load();
      repo.holdReads = true;
      await saves.toggle(savedPost(2, saved: false));
      await flushSaved();
      expect(list.state.posts, isEmpty);
      expect(repo.reads, hasLength(2));
      repo.reads.last.result.complete(savedPage([2]));
      await flushSaved();
      expect(list.state.posts.single.id, '2');
    },
  );
  test('old reader cannot override newer confirmed bookmark state', () async {
    final revision = saves.revision;
    final session = saves.session;
    await saves.toggle(savedPost(1));
    saves.accept(
      [savedPost(1)],
      requestRevision: revision,
      requestSession: session,
    );
    expect(saves.state.values['1'], false);
  });
  test(
    'logout clears list/bookmarks and ignores old mutation and load responses',
    () async {
      await list.load();
      repo.holdReads = true;
      repo.holdWrites = true;
      final old = list.refresh();
      final mutation = saves.toggle(savedPost(1));
      await preferences.clear();
      await flushSaved();
      expect(list.state.posts, isEmpty);
      expect(saves.state.values, isEmpty);
      expect(saves.state.pending, isEmpty);
      repo.reads.last.result.complete(savedPage([1]));
      repo.writes.last.result.complete(false);
      await old;
      await mutation;
      await flushSaved();
      expect(list.state.posts, isEmpty);
      expect(saves.state.values, isEmpty);
      expect((await saves.toggle(savedPost(1)))!.statusCode, 401);
    },
  );
  test('account switching drops previous list and late responses', () async {
    await list.load();
    repo.holdReads = true;
    final old = list.refresh();
    await preferences.saveToken('account-b');
    await flushSaved();
    expect(list.state.posts, isEmpty);
    expect(saves.state.values, isEmpty);
    final next = list.load();
    repo.reads.last.result.complete(savedPage([2]));
    await next;
    repo.reads[1].result.complete(savedPage([1]));
    await old;
    expect(list.state.posts.map((p) => p.id), ['2']);
    expect(saves.state.values.containsKey('1'), false);
  });
  test(
    'confirmed block filters Saved without changing Follow/Block controllers',
    () async {
      final follow = FollowCubit();
      final blocks = ConfirmedBlocks(follow: follow);
      final blockedList = SavedPostsCubit(
        saves: saves,
        repo: repo,
        blocks: blocks,
      );
      await blockedList.load();
      expect(blockedList.state.posts, hasLength(1));
      blocks.confirm(true);
      await flushSaved();
      expect(blockedList.state.posts, isEmpty);
      blocks.confirm(false);
      await flushSaved();
      expect(blockedList.state.posts.single.id, '1');
      await blockedList.close();
      await blocks.close();
      await follow.close();
    },
  );
  test(
    'account switching invalidates Home bookmark snapshots as well',
    () async {
      final feed = PostsCubit(postsRepo: repo, saves: saves);
      await feed.loadPosts();
      expect((feed.state as PostsLoaded).posts.single.isSaved, true);
      repo.stored = [];
      await preferences.saveToken('account-b');
      await flushSaved();
      expect((feed.state as PostsLoaded).posts.single.isSaved, false);
      expect(saves.state.values['1'], false);
      await preferences.remove('_token');
      await flushSaved();
      expect(feed.state, isA<PostsInitial>());
      await feed.close();
    },
  );

  test('closing controllers ignores asynchronous responses', () async {
    repo.holdReads = true;
    final pending = list.load();
    await list.close();
    repo.reads.last.result.complete(savedPage([1]));
    await pending;
    expect(list.state.posts, isEmpty);
  });
}
