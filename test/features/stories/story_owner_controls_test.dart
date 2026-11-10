import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/block/data/block_repo.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/stories/cubit/story_viewer_cubit.dart';
import 'package:travibe/features/stories/cubit/story_viewers_cubit.dart';
import 'package:travibe/features/stories/cubit/stories_cubit.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';
import 'package:travibe/features/stories/screens/story_viewer_screen.dart';
import 'fixtures.dart';
import 'story_viewer_test.dart' show viewerGroup, viewerDetail;
import 'story_publishing_test.dart'
    show StoryAdapter, repository, response, pageJson, groupJson;

Map<String, dynamic> viewerJson(int id) => {
  'id': id,
  'name': 'Viewer $id',
  'username': null,
  'country_code': null,
  'avatar_url': null,
  'viewed_at': '2026-10-21T13:59:26.595Z',
  'is_following': true,
  'follows_you': true,
  'has_liked': false,
};
Map<String, dynamic> viewersPage(List<int> ids, {int page = 1, int last = 1}) =>
    pageJson(ids.map(viewerJson).toList(), page: page, last: last);

class OwnerRepo extends StoriesRepo {
  int views = 0, deletes = 0;
  int refreshedCount = 12;
  final pages = <int>[];
  Future<void> Function(int)? viewHandler;
  Future<void> Function(int)? deleteHandler;
  Future<StoryDetail> Function(int)? detailHandler;
  Future<StoryViewersPage> Function(int)? viewersHandler;
  Future<StoriesPage> Function(int)? groupsHandler;
  @override
  Future<StoryDetail> getStory(int id) async {
    if (detailHandler != null) return detailHandler!(id);
    final json = viewerDetail(id)
      ..['views_count'] = views > 0 ? refreshedCount : 0;
    return StoryDetail.fromJson(json);
  }

  @override
  Future<void> recordView(int id) async {
    views++;
    await viewHandler?.call(id);
  }

  @override
  Future<void> deleteStory(int id) async {
    deletes++;
    await deleteHandler?.call(id);
  }

  @override
  Future<StoryViewersPage> getViewers(
    int id, {
    int page = 1,
    int perPage = 15,
  }) async {
    pages.add(page);
    return viewersHandler != null
        ? viewersHandler!(page)
        : StoryViewersPage.fromJson(viewersPage([8]));
  }

  @override
  Future<StoriesPage> getStories({int page = 1}) async => groupsHandler != null
      ? groupsHandler!(page)
      : StoriesPage.fromJson(pageJson([groupJson(7, storyId: 1)]));
}

class ViewerBlocksRepo extends BlockRepo {
  @override
  Future<BlockStatus> status(String id) async =>
      BlockStatus(userId: id, isBlocked: true);
}

void main() {
  final session = PreferencesManager();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await session.init();
    await session.saveToken('owner-test-session');
  });
  tearDown(() async => session.clear());
  test('exact owner endpoints, query and no view request body', () async {
    final adapter = StoryAdapter()
      ..handler = (request) async {
        if (request.method == 'DELETE') {
          return response({'message': 'Deleted'});
        }
        if (request.method == 'POST') {
          return response({
            'data': {'views_count': 12, 'viewed_at': '2026-10-21T13:00:00Z'},
          });
        }
        return response(viewersPage([8], page: 2, last: 2));
      };
    final repo = repository(adapter);
    await repo.recordView(4);
    expect(adapter.requests.first.path, 'stories/4/view');
    expect(adapter.requests.first.data, isNull);
    final page = await repo.getViewers(4, page: 2);
    expect(page.users.single.author.id, 8);
    expect(adapter.requests.last.queryParameters, {'page': 2, 'per_page': 15});
    await repo.deleteStory(4);
    expect(adapter.requests.last.method, 'DELETE');
    expect(adapter.requests.last.path, 'stories/4');
  });
  test('strict viewers parsing rejects malformed response', () {
    final json = viewersPage([8]);
    (json['data'] as List).first['is_following'] = 'yes';
    expect(() => StoryViewersPage.fromJson(json), throwsFormatException);
  });
  for (final code in [401, 403, 404]) {
    test('owner repository preserves HTTP $code errors', () async {
      final adapter = StoryAdapter()
        ..handler = (_) async => response({'message': 'Denied'}, status: code);
      final repo = repository(adapter);
      for (final operation in [
        () => repo.recordView(1),
        () => repo.getViewers(1),
        () => repo.deleteStory(1),
      ]) {
        await expectLater(
          operation(),
          throwsA(isA<ApiError>().having((e) => e.statusCode, 'status', code)),
        );
      }
    });
  }
  StoryViewerCubit viewer(
    OwnerRepo repo, {
    int? owner = 7,
    void Function(int, int)? onViewed,
    void Function(int)? onDeleted,
  }) => StoryViewerCubit(
    groups: [
      viewerGroup(7, [1, 2]),
    ],
    initialAuthorId: 7,
    repo: repo,
    currentUserId: owner,
    onViewed: onViewed,
    onDeleted: onDeleted,
  );
  test(
    'tracking waits for active decoded photo, deduplicates and uses server count',
    () async {
      final pending = Completer<void>();
      final repo = OwnerRepo()
        ..refreshedCount = 9
        ..viewHandler = ((_) => pending.future);
      final confirmed = <int>[];
      final cubit = viewer(repo, onViewed: (_, count) => confirmed.add(count));
      await cubit.start();
      expect(repo.views, 0);
      cubit.pause(true, reason: 'sheet');
      cubit.imageDisplayed(cubit.state.request);
      expect(repo.views, 0);
      cubit.pause(false, reason: 'sheet');
      expect(repo.views, 1);
      expect(cubit.state.viewsCount, isNull);
      cubit.pause(true);
      cubit.pause(false);
      expect(repo.views, 1);
      pending.complete();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.viewsCount, 9);
      expect(confirmed, [0, 9]);
      await cubit.previous();
      cubit.imageDisplayed(cubit.state.request);
      expect(repo.views, 1);
      await cubit.close();
    },
  );
  test(
    'failed view never manufactures count or confirmed seen event',
    () async {
      final repo = OwnerRepo()
        ..viewHandler = (_) async => throw ApiError(message: 'Offline');
      var called = false;
      final cubit = viewer(repo, onViewed: (_, _) => called = true);
      await cubit.start();
      cubit.imageDisplayed(cubit.state.request);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.viewsCount, isNull);
      expect(called, false);
      await cubit.close();
    },
  );
  test(
    'confirmed delete removes current item, advances and prevents duplicates',
    () async {
      final pending = Completer<void>();
      final deleted = <int>[];
      final repo = OwnerRepo()..deleteHandler = (_) => pending.future;
      final cubit = viewer(repo, onDeleted: deleted.add);
      await cubit.start();
      final first = cubit.deleteCurrent();
      await cubit.deleteCurrent();
      await cubit.next();
      expect(repo.deletes, 1);
      expect(cubit.state.paused, true);
      pending.complete();
      expect(await first, isNull);
      expect(deleted, [1]);
      expect(cubit.state.detail!.id, 2);
      expect(cubit.state.count, 1);
      await cubit.close();
    },
  );
  test(
    'non-owner cannot delete or load viewers even with is_mine true',
    () async {
      final repo = OwnerRepo();
      final cubit = viewer(repo, owner: 9);
      await cubit.start();
      expect(cubit.ownsCurrent, false);
      await cubit.deleteCurrent();
      expect(repo.deletes, 0);
      final list = StoryViewersCubit(
        storyId: 1,
        repo: repo,
        isOwner: () => cubit.ownsCurrent,
      );
      await list.refresh();
      expect(repo.pages, isEmpty);
      await list.close();
      await cubit.close();
    },
  );
  test(
    'timeout preserves current story; retry reconciles 404 without second delete',
    () async {
      final repo = OwnerRepo()
        ..deleteHandler = (_) async => throw ApiError(message: 'Timeout');
      final cubit = viewer(repo);
      await cubit.start();
      expect(
        (await cubit.deleteCurrent())!.message,
        contains('could not be confirmed'),
      );
      expect(cubit.state.detail!.id, 1);
      repo.detailHandler = (id) async {
        if (id == 1) throw ApiError(message: 'Gone', statusCode: 404);
        return StoryDetail.fromJson(viewerDetail(id));
      };
      expect(await cubit.deleteCurrent(), isNull);
      expect(repo.deletes, 1);
      expect(cubit.state.detail!.id, 2);
      await cubit.close();
    },
  );
  test(
    '403 and 404 delete failures retain current content with feedback',
    () async {
      final repo = OwnerRepo();
      final cubit = viewer(repo);
      await cubit.start();
      for (final code in [403, 404]) {
        repo.deleteHandler = (_) async =>
            throw ApiError(message: 'Unavailable', statusCode: code);
        expect((await cubit.deleteCurrent())!.statusCode, code);
        expect(cubit.state.detail!.id, 1);
        expect(cubit.deleting, false);
      }
      await cubit.close();
    },
  );
  test(
    'viewers pagination deduplicates, retries and blocks stale/session results',
    () async {
      final pending = Completer<StoryViewersPage>();
      final repo = OwnerRepo();
      repo.viewersHandler = (page) async => page == 1
          ? StoryViewersPage.fromJson(viewersPage([8], last: 2))
          : pending.future;
      final cubit = StoryViewersCubit(
        storyId: 1,
        repo: repo,
        isOwner: () => true,
      );
      await cubit.refresh();
      final second = cubit.loadMore();
      await cubit.loadMore();
      expect(repo.pages, [1, 2]);
      pending.complete(
        StoryViewersPage.fromJson(viewersPage([8, 9], page: 2, last: 2)),
      );
      await second;
      expect(cubit.state.users.map((u) => u.author.id), [8, 9]);
      final late = Completer<StoryViewersPage>();
      repo.viewersHandler = (_) => late.future;
      final stale = cubit.refresh();
      await session.saveToken('another-owner');
      late.complete(StoryViewersPage.fromJson(viewersPage([10])));
      await stale;
      expect(cubit.state.users, isEmpty);
      await cubit.close();
    },
  );
  test(
    'viewers 403 clears private rows; empty response and retry are supported',
    () async {
      final repo = OwnerRepo();
      final cubit = StoryViewersCubit(
        storyId: 1,
        repo: repo,
        isOwner: () => true,
      );
      await cubit.refresh();
      expect(cubit.state.users, hasLength(1));
      repo.viewersHandler = (_) async =>
          throw ApiError(message: 'Denied', statusCode: 403);
      await cubit.refresh();
      expect(cubit.state.users, isEmpty);
      expect(cubit.state.error!.statusCode, 403);
      repo.viewersHandler = (_) async =>
          StoryViewersPage.fromJson(viewersPage([]));
      await cubit.refresh();
      expect(cubit.state.users, isEmpty);
      expect(cubit.state.error, isNull);
      await cubit.close();
    },
  );
  test(
    'confirmed viewing and deletion survive stale Home reads, reset on session change',
    () async {
      final pending = Completer<StoriesPage>();
      final repo = OwnerRepo()..groupsHandler = (_) => pending.future;
      final cubit = StoriesCubit(repo: repo);
      final read = cubit.refresh();
      cubit.confirmedView(1, 12);
      pending.complete(
        StoriesPage.fromJson(pageJson([groupJson(7, storyId: 1)])),
      );
      await read;
      expect(cubit.state.groups.single.hasUnseen, false);
      expect(cubit.state.groups.single.stories.single.viewsCount, 12);
      cubit.confirmedDelete(1);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.groups, isEmpty);
      await session.saveToken('other-account');
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.groups.single.hasUnseen, true);
      await cubit.close();
    },
  );
  test(
    'session changes ignore in-flight view and delete completions',
    () async {
      final viewed = Completer<void>();
      final removed = Completer<void>();
      final repo = OwnerRepo()
        ..viewHandler = ((_) => viewed.future)
        ..deleteHandler = ((_) => removed.future);
      var callbacks = 0;
      final cubit = viewer(
        repo,
        onViewed: (_, _) => callbacks++,
        onDeleted: (_) => callbacks++,
      );
      await cubit.start();
      cubit.imageDisplayed(cubit.state.request);
      final deletion = cubit.deleteCurrent();
      await session.saveToken('different-session');
      viewed.complete();
      removed.complete();
      await deletion;
      expect(callbacks, 0);
      expect(cubit.state.status, StoryViewerStatus.finished);
      await cubit.close();
    },
  );

  test(
    'blocked viewers are removed and cannot return through a late page',
    () async {
      final follow = FollowCubit();
      final blocks = BlockCubit(follow: follow, repo: ViewerBlocksRepo());
      final pending = Completer<StoryViewersPage>();
      final repo = OwnerRepo()
        ..viewersHandler = ((page) async => page == 1
            ? StoryViewersPage.fromJson(viewersPage([8], last: 2))
            : pending.future);
      final cubit = StoryViewersCubit(
        storyId: 1,
        repo: repo,
        isOwner: () => true,
        blocks: blocks,
      );
      await cubit.refresh();
      final next = cubit.loadMore();
      await blocks.checkStatus('8');
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.users, isEmpty);
      pending.complete(
        StoryViewersPage.fromJson(viewersPage([8, 9], page: 2, last: 2)),
      );
      await next;
      expect(cubit.state.users.single.author.id, 9);
      await cubit.close();
      await blocks.close();
      await follow.close();
    },
  );
  test('pagination failure keeps rows and retries the same cursor', () async {
    final repo = OwnerRepo()
      ..viewersHandler = ((page) async => page == 1
          ? StoryViewersPage.fromJson(viewersPage([8], last: 2))
          : throw ApiError(message: 'Offline'));
    final cubit = StoryViewersCubit(
      storyId: 1,
      repo: repo,
      isOwner: () => true,
    );
    await cubit.refresh();
    await cubit.loadMore();
    expect(cubit.state.users.single.author.id, 8);
    expect(cubit.state.error, isNotNull);
    repo.viewersHandler = (page) async =>
        StoryViewersPage.fromJson(viewersPage([9], page: page, last: 2));
    await cubit.loadMore();
    expect(repo.pages, [1, 2, 2]);
    expect(cubit.state.users.length, 2);
    await cubit.close();
  });
  test(
    'deleting final story finishes and confirmed writes still update Home after route disposal',
    () async {
      final pending = Completer<void>();
      final repo = OwnerRepo()..deleteHandler = ((_) => pending.future);
      final deleted = <int>[];
      final cubit = StoryViewerCubit(
        groups: [
          viewerGroup(7, [1]),
        ],
        initialAuthorId: 7,
        currentUserId: 7,
        repo: repo,
        onDeleted: deleted.add,
      );
      await cubit.start();
      final operation = cubit.deleteCurrent();
      await cubit.close();
      pending.complete();
      await operation;
      expect(deleted, [1]);
      final last = StoryViewerCubit(
        groups: [
          viewerGroup(7, [1]),
        ],
        initialAuthorId: 7,
        currentUserId: 7,
        repo: OwnerRepo(),
      );
      await last.start();
      await last.deleteCurrent();
      expect(last.state.status, StoryViewerStatus.finished);
      await last.close();
    },
  );
  Future<void> open(
    WidgetTester tester,
    OwnerRepo repo, {
    int owner = 7,
    BlockCubit? blocks,
    FollowCubit? follow,
    double textScale = 1,
  }) async {
    final photo = MemoryImage(photoBytes());
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StoryViewerScreen(
                    groups: [
                      viewerGroup(7, [1, 2]),
                    ],
                    initialAuthorId: 7,
                    currentUserId: owner,
                    repo: repo,
                    imageProvider: (_) => photo,
                    blocks: blocks,
                    follow: follow,
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => precacheImage(photo, tester.element(find.text('Open'))),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
  }

  testWidgets(
    'owner controls, viewers sheet, Follow pill and playback pause/dismiss',
    (tester) async {
      final follow = FollowCubit();
      final blocks = BlockCubit(follow: follow);
      final repo = OwnerRepo();
      await open(tester, repo, blocks: blocks, follow: follow);
      expect(find.byKey(const ValueKey('story-views')), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('story-views')));
      await tester.pumpAndSettle();
      expect(find.text('12 Views'), findsOneWidget);
      expect(
        find.text('Only you can see who viewed your story.'),
        findsOneWidget,
      );
      expect(find.text('Viewer 8'), findsOneWidget);
      expect(find.text('Following'), findsOneWidget);
      await tester.pump(const Duration(seconds: 8));
      expect(find.text('12 Views'), findsOneWidget);
      await tester.tapAt(const Offset(10, 20));
      await tester.pumpAndSettle();
      expect(find.text('12 Views'), findsNothing);
      expect(find.byType(StoryViewerScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await blocks.close();
      await follow.close();
    },
  );
  testWidgets(
    'delete requires confirmation, cancel preserves story, confirm advances',
    (tester) async {
      final repo = OwnerRepo();
      await open(tester, repo);
      await tester.tap(find.byKey(const ValueKey('story-owner-options')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete story'));
      await tester.pumpAndSettle();
      expect(repo.deletes, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.deletes, 0);
      await tester.tap(find.byKey(const ValueKey('story-owner-options')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete story'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(repo.deletes, 1);
      expect(find.byType(StoryViewerScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'public viewer hides owner controls and session change closes sheets and viewer',
    (tester) async {
      final repo = OwnerRepo();
      await open(tester, repo, owner: 8);
      expect(find.byKey(const ValueKey('story-views')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await open(tester, repo);
      await tester.tap(find.byKey(const ValueKey('story-views')));
      await tester.pumpAndSettle();
      await session.saveToken('switched-account');
      await tester.pumpAndSettle();
      expect(find.byType(StoryViewerScreen), findsNothing);
      expect(find.text('12 Views'), findsNothing);
      expect(find.text('Open'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'one owner sheet instance; session change during delete confirmation closes all overlays',
    (tester) async {
      final repo = OwnerRepo();
      await open(tester, repo);
      await tester.tap(find.byKey(const ValueKey('story-owner-options')));
      await tester.tap(
        find.byKey(const ValueKey('story-owner-options')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.text('Delete story'), findsOneWidget);
      await tester.tap(find.text('Delete story'));
      await tester.pumpAndSettle();
      await session.saveToken('new-session-during-dialog');
      await tester.pumpAndSettle();
      expect(find.text('Delete story?'), findsNothing);
      expect(find.byType(StoryViewerScreen), findsNothing);
      expect(repo.deletes, 0);
      expect(find.text('Open'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'owner controls and viewers remain scrollable on small screens with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final follow = FollowCubit();
      final blocks = BlockCubit(follow: follow);
      await open(
        tester,
        OwnerRepo(),
        follow: follow,
        blocks: blocks,
        textScale: 2.5,
      );
      await tester.tap(find.byKey(const ValueKey('story-views')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Viewer 8'),
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('Viewer 8'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await blocks.close();
      await follow.close();
    },
  );
}
