import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/dio_client.dart';
import 'package:travibe/core/media/media_upload_service.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/home/widgets/home_stories.dart';
import 'package:travibe/features/stories/cubit/stories_cubit.dart';
import 'package:travibe/features/stories/cubit/story_editor_cubit.dart';
import 'package:travibe/features/stories/cubit/story_publish_cubit.dart';
import 'package:travibe/features/stories/data/story_audience.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';
import 'package:travibe/features/stories/data/story_elements.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';
import 'package:travibe/features/stories/screens/story_editor_screen.dart';

import '../../core/media/media_upload_test.dart' as media;
import 'fixtures.dart';

Map<String, dynamic> storyDetail({
  int id = 3,
  int mediaId = 19,
  String visibility = 'public',
}) => {
  'id': id,
  'user_id': 7,
  'user': {'id': 7, 'name': 'Traveler', 'avatar_url': null},
  'media': [
    {
      'id': mediaId,
      'url': 'https://example.invalid/photo.png',
      'thumbnail_url': null,
    },
  ],
  'visibility': visibility,
  'location_name': null,
  'elements': [],
  'views_count': 0,
  'likes_count': 0,
  'is_liked': false,
  'is_mine': true,
  'has_seen': false,
  'created_at': '2026-10-21T10:00:00Z',
  'expires_at': '2026-10-22T10:00:00Z',
};
Map<String, dynamic> groupJson(int userId, {int? storyId}) => {
  'user': {'id': userId, 'name': 'Traveler $userId', 'avatar_url': null},
  'has_unseen': true,
  'stories': [
    {
      'id': storyId ?? userId,
      'thumbnail_url': null,
      'created_at': null,
      'expires_at': '2026-10-22T10:00:00Z',
      'views_count': 0,
      'has_seen': false,
    },
  ],
};
Map<String, dynamic> pageJson(
  List<Map<String, dynamic>> groups, {
  int page = 1,
  int last = 1,
}) => {
  'data': groups,
  'links': {'first': null, 'last': null, 'next': null, 'prev': null},
  'meta': {
    'current_page': page,
    'last_page': last,
    'per_page': 15,
    'total': groups.length,
  },
};
ResponseBody response(dynamic body, {int status = 200}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

class StoryAdapter implements HttpClientAdapter {
  Future<ResponseBody> Function(RequestOptions) handler = (_) async =>
      response({'data': storyDetail()}, status: 201);
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

StoriesRepo repository(StoryAdapter adapter) {
  final client = DioClient();
  client.dio.httpClientAdapter = adapter;
  return StoriesRepo(client: client);
}

class PageRepo extends StoriesRepo {
  final calls = <int>[];
  Future<StoriesPage> Function(int) handler = (page) async =>
      StoriesPage.fromJson(pageJson([]));
  @override
  Future<StoriesPage> getStories({int page = 1}) {
    calls.add(page);
    return handler(page);
  }
}

void main() {
  setUp(() {
    ScreenUtil.configure(
      data: const MediaQueryData(size: Size(390, 844)),
      designSize: const Size(390, 844),
      minTextAdapt: false,
      splitScreenMode: false,
    );
  });

  final session = PreferencesManager();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await session.init();
    await session.saveToken('test-session');
  });
  tearDown(() async {
    await session.clear();
  });

  test(
    'v1 overlay JSON round trip preserves IDs, text, normalized centers and scales',
    () {
      final editor = StoryEditorCubit(draft());
      addTearDown(editor.close);
      editor.saveText('Hello 🌍\nTravibe');
      final first = editor.state.layers.single as StoryTextLayer;
      editor.commitTransform(first.id, const Offset(.21, .73), 1.6);
      final encoded = StoryElements.encode(editor.state.layers);
      final restored = StoryElements.decode(jsonDecode(jsonEncode(encoded)));
      expect(restored.single.id, first.id);
      expect(restored.single.text, first.text);
      expect(restored.single.center, const Offset(.21, .73));
      expect(restored.single.scale, 1.6);
      expect(encoded.single['style'], StoryElements.style);
      final next = StoryEditorCubit(editor.state.withLayers(restored));
      addTearDown(next.close);
      next.saveText('New');
      expect(next.state.layers.map((l) => l.id).toSet(), hasLength(2));
    },
  );
  test(
    'overlay count, nonfinite values, duplicate IDs and unsupported style/version rejected',
    () {
      const layer = StoryTextLayer(id: 'text', text: 'Trip');
      expect(
        () => StoryElements.encode(List.filled(51, layer)),
        throwsFormatException,
      );
      expect(() => StoryElements.encode([layer, layer]), throwsFormatException);
      expect(
        () => StoryElements.encode([layer.copyWith(scale: double.nan)]),
        throwsFormatException,
      );
      final json = StoryElements.encode([layer]);
      json.single['version'] = 2;
      expect(() => StoryElements.decode(json), throwsFormatException);
      json.single['version'] = 1;
      json.single['style'] = {};
      expect(() => StoryElements.decode(json), throwsFormatException);
    },
  );
  test(
    'POST uses one positive media ID and exact Public/Followers visibility',
    () async {
      final adapter = StoryAdapter();
      final repo = repository(adapter);
      final result = await repo.create(
        CreateStoryRequest(mediaId: 19, draft: draft()),
      );
      expect(result.id, 3);
      expect(result.media.id, 19);
      expect(adapter.requests.single.path, 'stories');
      expect(
        adapter.requests.single.headers['Authorization'],
        startsWith('Bearer '),
      );
      expect(adapter.requests.single.data, {
        'media_ids': [19],
        'visibility': 'public',
        'location_name': null,
        'elements': [],
      });
      expect(
        () => CreateStoryRequest(mediaId: 0, draft: draft()).toJson(),
        throwsFormatException,
      );
      adapter.handler = (_) async =>
          response({'data': storyDetail(visibility: 'followers')}, status: 201);
      final followers = await repo.create(
        CreateStoryRequest(
          mediaId: 19,
          draft: draft().withAudience(StoryAudience.followers),
        ),
      );
      expect(followers.visibility, 'followers');
      expect((adapter.requests.last.data as Map)['visibility'], 'followers');
      expect(adapter.requests, hasLength(2));
    },
  );
  test(
    'detail GET and paginated author GET parse documented nullable values',
    () async {
      final adapter = StoryAdapter();
      final repo = repository(adapter);
      adapter.handler = (request) async => request.path == 'stories/3'
          ? response({'data': storyDetail()})
          : response(pageJson([groupJson(8)], page: 2, last: 3));
      expect((await repo.getStory(3)).visibility, 'public');
      final page = await repo.getStories(page: 2);
      expect(adapter.requests.last.queryParameters, {'page': 2});
      expect(page.hasMore, true);
      expect(page.groups.single.user.avatarUrl, null);
      expect(page.groups.single.stories.single.createdAt, null);
    },
  );
  for (final status in [401, 403, 404, 422]) {
    test('repository preserves HTTP $status and validation messages', () async {
      final adapter = StoryAdapter()
        ..handler = (_) async => response({
          'message': 'Denied',
          'errors': {
            'stories': ['Maximum 10 active stories'],
          },
        }, status: status);
      final repo = repository(adapter);
      await expectLater(
        repo.create(CreateStoryRequest(mediaId: 19, draft: draft())),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'HTTP', status)),
      );
    });
  }
  test(
    'unexpected GET shape is an error; malformed creation is ambiguous and cannot be repeated',
    () async {
      final adapter = StoryAdapter()
        ..handler = (_) async => response({'wrong': []});
      final repo = repository(adapter);
      await expectLater(repo.getStories(), throwsA(isA<ApiError>()));
      adapter.handler = (_) async => response({'data': {}}, status: 201);
      await expectLater(
        repo.create(CreateStoryRequest(mediaId: 19, draft: draft())),
        throwsA(isA<StoryCreationUncertain>()),
      );
    },
  );

  test(
    'original-photo upload → finalize → ready → POST 201 → Home refresh, one submission',
    () async {
      final api = media.MediaApi()..statuses = ['processing', 'ready'];
      final storage = media.StorageAdapter();
      final uploads = MediaUploadService(
        api: api,
        storageAdapter: storage,
        wait: (_) async {},
      );
      addTearDown(uploads.close);
      final adapter = StoryAdapter();
      final home = StoriesCubit(repo: PageRepo());
      addTearDown(home.close);
      var refreshes = 0;
      final cubit = StoryPublishCubit(
        repo: repository(adapter),
        uploads: uploads,
        onPublished: () async {
          refreshes++;
          await home.refresh();
        },
      );
      addTearDown(cubit.close);
      final value = draft().withLayers([
        const StoryTextLayer(id: 'text', text: 'Hello'),
      ]);
      final states = <StoryPublishStatus>[];
      final subscription = cubit.stream.listen((s) => states.add(s.status));
      addTearDown(subscription.cancel);
      final first = cubit.publish(value);
      await cubit.publish(value);
      await first;
      expect(cubit.state.status, StoryPublishStatus.success);
      expect(
        states,
        containsAll([
          StoryPublishStatus.uploading,
          StoryPublishStatus.processing,
          StoryPublishStatus.publishing,
        ]),
      );
      expect(storage.requests, 1);
      expect(storage.bytes, photoBytes());
      expect(
        storage.request!.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
      expect(api.calls.where((c) => c == 'POST media/presign'), hasLength(1));
      expect(api.calls.where((c) => c.endsWith('/finalize')), hasLength(1));
      expect(adapter.requests, hasLength(1));
      expect(
        (adapter.requests.single.data as Map)['elements'],
        StoryElements.encode(value.layers),
      );
      expect(refreshes, 1);
      await cubit.publish(value);
      expect(adapter.requests, hasLength(1));
    },
  );
  test(
    '422 active-story limit keeps draft and retry reuses existing ready media without PUT/finalize',
    () async {
      final api = media.MediaApi()..statuses = ['ready'];
      final storage = media.StorageAdapter();
      final uploads = MediaUploadService(
        api: api,
        storageAdapter: storage,
        wait: (_) async {},
      );
      addTearDown(uploads.close);
      final adapter = StoryAdapter()
        ..handler = (_) async => response({
          'message': 'Maximum 10 active stories',
          'errors': {
            'stories': ['Maximum 10 active stories'],
          },
        }, status: 422);
      final cubit = StoryPublishCubit(
        repo: repository(adapter),
        uploads: uploads,
      );
      addTearDown(cubit.close);
      final value = draft().withLayers([
        const StoryTextLayer(id: 'text', text: 'Keep me'),
      ]);
      await cubit.publish(value);
      expect(cubit.state.error!.statusCode, 422);
      expect(cubit.state.error!.message, 'Maximum 10 active stories');
      expect(value.layers.single.id, 'text');
      adapter.handler = (_) async =>
          response({'data': storyDetail()}, status: 201);
      await cubit.publish(value);
      expect(cubit.state.status, StoryPublishStatus.success);
      expect(storage.requests, 1);
      expect(api.calls.where((c) => c == 'POST media/presign'), hasLength(1));
      expect(api.calls.where((c) => c.endsWith('/finalize')), hasLength(1));
      expect(
        api.calls.where((c) => c == 'GET media/19').length,
        greaterThan(1),
      );
    },
  );
  test(
    'confirmed storage failure preserves input, prevents POST, and allows explicit retry',
    () async {
      final api = media.MediaApi()..statuses = ['ready'];
      final storage = media.StorageAdapter()..status = 403;
      final uploads = MediaUploadService(
        api: api,
        storageAdapter: storage,
        wait: (_) async {},
      );
      addTearDown(uploads.close);
      final adapter = StoryAdapter();
      final cubit = StoryPublishCubit(
        repo: repository(adapter),
        uploads: uploads,
      );
      addTearDown(cubit.close);
      final value = draft();
      await cubit.publish(value);
      expect(cubit.state.status, StoryPublishStatus.failure);
      expect(adapter.requests, isEmpty);
      expect(api.calls.where((c) => c.endsWith('/finalize')), isEmpty);
      expect(value.image.bytes, photoBytes());
      storage.status = 200;
      await cubit.publish(value);
      expect(cubit.state.status, StoryPublishStatus.success);
    },
  );
  test(
    'expired presign never PUTs or publishes; explicit retry gets fresh authorization',
    () async {
      final api = media.MediaApi()..statuses = ['ready'];
      api.presign['expires_at'] = '2000-01-01T00:00:00Z';
      final storage = media.StorageAdapter();
      final uploads = MediaUploadService(
        api: api,
        storageAdapter: storage,
        wait: (_) async {},
      );
      addTearDown(uploads.close);
      final adapter = StoryAdapter();
      final cubit = StoryPublishCubit(
        repo: repository(adapter),
        uploads: uploads,
      );
      addTearDown(cubit.close);
      final value = draft();
      await cubit.publish(value);
      expect(cubit.state.error!.message, contains('expired'));
      expect(storage.requests, 0);
      expect(adapter.requests, isEmpty);
      api.presign['expires_at'] = '2030-01-01T00:00:00Z';
      await cubit.publish(value);
      expect(cubit.state.status, StoryPublishStatus.success);
      expect(storage.requests, 1);
    },
  );
  test(
    'failed media processing preserves draft and never submits a Story',
    () async {
      final api = media.MediaApi()..statuses = ['processing', 'failed'];
      final storage = media.StorageAdapter();
      final uploads = MediaUploadService(
        api: api,
        storageAdapter: storage,
        wait: (_) async {},
      );
      addTearDown(uploads.close);
      final adapter = StoryAdapter();
      final cubit = StoryPublishCubit(
        repo: repository(adapter),
        uploads: uploads,
      );
      addTearDown(cubit.close);
      final value = draft();
      await cubit.publish(value);
      expect(cubit.state.status, StoryPublishStatus.failure);
      expect(adapter.requests, isEmpty);
      expect(value.image.bytes, photoBytes());
      api.statuses = ['ready'];
      await cubit.publish(value);
      expect(cubit.state.status, StoryPublishStatus.success);
    },
  );
  test(
    'account change clears loaded groups and invalidates pending pagination',
    () async {
      final oldPage = Completer<StoriesPage>();
      final repo = PageRepo()
        ..handler = (page) async => page == 1
            ? StoriesPage.fromJson(pageJson([groupJson(8)], last: 2))
            : oldPage.future;
      final cubit = StoriesCubit(repo: repo);
      addTearDown(cubit.close);
      await cubit.load();
      final more = cubit.loadMore();
      final nextPage = Completer<StoriesPage>();
      repo.handler = (_) => nextPage.future;
      await session.saveToken('changed-account-test-session');
      expect(cubit.state.groups, isEmpty);
      nextPage.complete(StoriesPage.fromJson(pageJson([groupJson(9)])));
      oldPage.complete(
        StoriesPage.fromJson(pageJson([groupJson(10)], page: 2, last: 2)),
      );
      await more;
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.groups.map((g) => g.user.id), [9]);
    },
  );
  test(
    'Followers publishes successfully without changing the selected audience',
    () async {
      final api = media.MediaApi()..statuses = ['processing', 'ready'];
      final storage = media.StorageAdapter();
      final uploads = MediaUploadService(
        api: api,
        storageAdapter: storage,
        wait: (_) async {},
      );
      addTearDown(uploads.close);
      final adapter = StoryAdapter()
        ..handler = (_) async => response({
          'data': storyDetail(visibility: 'followers'),
        }, status: 201);
      final cubit = StoryPublishCubit(
        repo: repository(adapter),
        uploads: uploads,
      );
      addTearDown(cubit.close);
      final editor = StoryEditorCubit(draft())
        ..setAudience(StoryAudience.followers);
      addTearDown(editor.close);
      editor.saveText('Followers only');
      final selected = editor.state;
      await cubit.publish(selected);
      expect(cubit.state.status, StoryPublishStatus.success);
      expect(cubit.state.story!.visibility, 'followers');
      expect(editor.state, same(selected));
      expect(editor.state.audience, StoryAudience.followers);
      expect(adapter.requests.single.data['visibility'], 'followers');
      expect(storage.requests, 1);
    },
  );
  test(
    'Followers rejection preserves draft and retries as Followers with the same ready media',
    () async {
      final api = media.MediaApi()..statuses = ['ready'];
      final storage = media.StorageAdapter();
      final uploads = MediaUploadService(
        api: api,
        storageAdapter: storage,
        wait: (_) async {},
      );
      addTearDown(uploads.close);
      final adapter = StoryAdapter()
        ..handler = (_) async => response({
          'message': 'Visibility rejected',
          'errors': {
            'visibility': ['Visibility rejected'],
          },
        }, status: 422);
      final cubit = StoryPublishCubit(
        repo: repository(adapter),
        uploads: uploads,
      );
      addTearDown(cubit.close);
      final editor = StoryEditorCubit(draft())
        ..setAudience(StoryAudience.followers);
      addTearDown(editor.close);
      editor.saveText('Keep this');
      final selected = editor.state;
      await cubit.publish(selected);
      expect(cubit.state.error!.statusCode, 422);
      expect(editor.state, same(selected));
      expect(editor.state.audience, StoryAudience.followers);
      adapter.handler = (_) async =>
          response({'data': storyDetail(visibility: 'followers')}, status: 201);
      await cubit.publish(editor.state);
      expect(cubit.state.status, StoryPublishStatus.success);
      expect(adapter.requests.map((r) => r.data['visibility']), [
        'followers',
        'followers',
      ]);
      expect(storage.requests, 1);
      expect(api.calls.where((c) => c == 'POST media/presign'), hasLength(1));
      expect(api.calls.where((c) => c.endsWith('/finalize')), hasLength(1));
    },
  );
  test(
    'a mismatched successful visibility is never accepted as an audience fallback',
    () async {
      final adapter = StoryAdapter();
      await expectLater(
        repository(adapter).create(
          CreateStoryRequest(
            mediaId: 19,
            draft: draft().withAudience(StoryAudience.followers),
          ),
        ),
        throwsA(isA<StoryCreationUncertain>()),
      );
      expect(adapter.requests.single.data['visibility'], 'followers');
    },
  );
  test(
    'ambiguous creation blocks repeat POST and does not claim success',
    () async {
      final api = media.MediaApi()..statuses = ['ready'];
      final storage = media.StorageAdapter();
      final uploads = MediaUploadService(
        api: api,
        storageAdapter: storage,
        wait: (_) async {},
      );
      addTearDown(uploads.close);
      final adapter = StoryAdapter()
        ..handler = (r) async => throw DioException(
          requestOptions: r,
          type: DioExceptionType.receiveTimeout,
        );
      final cubit = StoryPublishCubit(
        repo: repository(adapter),
        uploads: uploads,
      );
      addTearDown(cubit.close);
      await cubit.publish(draft());
      expect(cubit.state.uncertain, true);
      await cubit.publish(draft());
      expect(adapter.requests, hasLength(1));
      expect(storage.requests, 1);
    },
  );
  for (final dispose in [false, true]) {
    test(
      'publication ignores late response after ${dispose ? 'disposal' : 'account switch'}',
      () async {
        final api = media.MediaApi()..statuses = ['ready'];
        final storage = media.StorageAdapter();
        final uploads = MediaUploadService(
          api: api,
          storageAdapter: storage,
          wait: (_) async {},
        );
        addTearDown(uploads.close);
        final ready = Completer<ResponseBody>();
        final requested = Completer<void>();
        final adapter = StoryAdapter()
          ..handler = (_) {
            requested.complete();
            return ready.future;
          };
        var refreshes = 0;
        final cubit = StoryPublishCubit(
          repo: repository(adapter),
          uploads: uploads,
          onPublished: () async {
            refreshes++;
          },
        );
        final pending = cubit.publish(draft());
        await requested.future;
        if (dispose) {
          await cubit.close();
        } else {
          await session.saveToken('different-test-session');
        }
        ready.complete(response({'data': storyDetail()}, status: 201));
        await pending;
        expect(refreshes, 0);
        expect(cubit.state.status, isNot(StoryPublishStatus.success));
        if (!dispose) {
          expect(cubit.state.sessionEnded, true);
          await cubit.close();
        }
      },
    );
  }

  test(
    'Home pagination deduplicates groups/stories and preserves backend ordering',
    () async {
      final repo = PageRepo()
        ..handler = (page) async => StoriesPage.fromJson(
          pageJson(
            page == 1
                ? [groupJson(8), groupJson(7)]
                : [groupJson(8, storyId: 18), groupJson(9)],
            page: page,
            last: 2,
          ),
        );
      final cubit = StoriesCubit(repo: repo);
      addTearDown(cubit.close);
      await Future.wait([cubit.load(), cubit.load()]);
      expect(repo.calls, [1]);
      await Future.wait([cubit.loadMore(), cubit.loadMore()]);
      expect(repo.calls, [1, 2]);
      expect(cubit.state.groups.map((g) => g.user.id), [8, 7, 9]);
      expect(cubit.state.groups.first.stories.map((s) => s.id), [8, 18]);
      expect(cubit.state.hasMore, false);
      await cubit.refresh();
      expect(cubit.state.groups.map((g) => g.user.id), [8, 7]);
    },
  );
  test(
    'refresh invalidates stale pagination and supports empty, error and retry',
    () async {
      final pending = Completer<StoriesPage>();
      final repo = PageRepo();
      repo.handler = (p) async => p == 1
          ? StoriesPage.fromJson(pageJson([groupJson(8)], last: 2))
          : pending.future;
      final cubit = StoriesCubit(repo: repo);
      addTearDown(cubit.close);
      await cubit.load();
      final more = cubit.loadMore();
      repo.handler = (_) async => StoriesPage.fromJson(pageJson([]));
      await cubit.refresh();
      pending.complete(
        StoriesPage.fromJson(pageJson([groupJson(9)], page: 2, last: 2)),
      );
      await more;
      expect(cubit.state.groups, isEmpty);
      repo.handler = (_) async => throw ApiError(message: 'offline');
      await cubit.refresh();
      expect(cubit.state.error!.message, 'offline');
      repo.handler = (_) async =>
          StoriesPage.fromJson(pageJson([groupJson(10)]));
      await cubit.refresh();
      expect(cubit.state.groups.single.user.id, 10);
    },
  );
  test(
    'logout clears Home immediately; stale response cannot restore another account',
    () async {
      final pending = Completer<StoriesPage>();
      final repo = PageRepo()..handler = (_) => pending.future;
      final cubit = StoriesCubit(repo: repo);
      addTearDown(cubit.close);
      final load = cubit.load();
      await session.clear();
      pending.complete(StoriesPage.fromJson(pageJson([groupJson(8)])));
      await load;
      expect(cubit.state.groups, isEmpty);
      expect(cubit.state.loading, false);
      repo.handler = (_) async =>
          StoriesPage.fromJson(pageJson([groupJson(9)]));
      await session.saveToken('next-test-session');
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.groups.single.user.id, 9);
    },
  );
  test(
    'blocking hides author immediately and stale reads cannot restore them',
    () async {
      final follow = FollowCubit();
      final blocks = BlockCubit(follow: follow);
      addTearDown(blocks.close);
      addTearDown(follow.close);
      final stale = Completer<StoriesPage>();
      final repo = PageRepo()
        ..handler = (page) async => page == 1
            ? StoriesPage.fromJson(
                pageJson([groupJson(8), groupJson(9)], last: 2),
              )
            : stale.future;
      final cubit = StoriesCubit(repo: repo, blocks: blocks);
      addTearDown(cubit.close);
      await cubit.load();
      final more = cubit.loadMore();
      // State notification simulates the existing shared BlockCubit's confirmed mutation.
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      blocks.emit(BlockState(blocked: {'8': true}));
      await Future<void>.delayed(Duration.zero);
      stale.complete(
        StoriesPage.fromJson(pageJson([groupJson(8)], page: 2, last: 2)),
      );
      await more;
      expect(cubit.state.groups.map((g) => g.user.id), [9]);
    },
  );
  testWidgets(
    'Home renders owner first, unseen rings, retry and no functional viewer',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeStories(
              stories: [
                StoryGroup.fromJson(groupJson(8)),
                StoryGroup.fromJson(groupJson(7)),
              ],
              currentUserId: 7,
              error: 'offline',
              onRetry: () {},
            ),
          ),
        ),
      );
      expect(
        tester.getTopLeft(find.text('You')).dx,
        lessThan(tester.getTopLeft(find.text('Traveler 8')).dx),
      );
      expect(find.byKey(const ValueKey('stories-retry')), findsOneWidget);
      await tester.tap(find.text('Traveler 8'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeStories), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final hosted in [true, false]) {
    testWidgets(
      'one Post tap publishes, refreshes Home, closes editor and shows success'
      '${hosted ? ' (host toast)' : ' (editor SnackBar)'}',
      (tester) async {
        final api = media.MediaApi()..statuses = ['ready'];
        final storage = media.StorageAdapter();
        final uploads = MediaUploadService(
          api: api,
          storageAdapter: storage,
          wait: (_) async {},
        );
        addTearDown(uploads.close);
        final adapter = StoryAdapter();
        var refreshed = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => StoryEditorScreen(
                        draft: draft(),
                        storiesRepo: repository(adapter),
                        uploads: uploads,
                        onPublished: hosted
                            ? () async {
                                refreshed++;
                              }
                            : null,
                      ),
                    ),
                  ),
                  child: const Text('Open editor'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open editor'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('story-post')));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(adapter.requests, hasLength(1));
        expect(refreshed, hosted ? 1 : 0);
        expect(find.byType(StoryEditorScreen), findsNothing);
        // A host (Home) passing onPublished owns the success toast.
        expect(
          find.text('Story published'),
          hosted ? findsNothing : findsOneWidget,
        );
      },
    );
  }
  testWidgets(
    'Followers enables Post and shows the supported audience descriptions',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: StoryEditorScreen(
            draft: draft().withAudience(StoryAudience.followers),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('story-post')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const ValueKey('story-audience')));
      await tester.pumpAndSettle();
      expect(
        find.text('Only people who follow you can see your story.'),
        findsOneWidget,
      );
    },
  );
}
