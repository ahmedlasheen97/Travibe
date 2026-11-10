import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/home/widgets/home_stories.dart';
import 'package:travibe/features/stories/cubit/story_viewer_cubit.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';
import 'package:travibe/features/stories/data/story_elements.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';
import 'package:travibe/features/stories/screens/story_viewer_screen.dart';
import 'package:travibe/features/stories/widgets/story_canvas.dart';
import 'package:travibe/features/stories/widgets/story_viewer_canvas.dart';

import 'fixtures.dart';
import 'story_publishing_test.dart'
    show groupJson, storyDetail, StoryAdapter, repository, response;

StoryGroup viewerGroup(int author, List<int> ids, {DateTime? expiry}) {
  final json = groupJson(author);
  json['stories'] = [
    for (final id in ids)
      {
        'id': id,
        'thumbnail_url': 'https://example.invalid/thumbnail-$id.png',
        'created_at': null,
        'expires_at': (expiry ?? DateTime.now().add(const Duration(hours: 1)))
            .toIso8601String(),
        'views_count': 0,
        'has_seen': false,
      },
  ];
  return StoryGroup.fromJson(json);
}

Map<String, dynamic> viewerDetail(
  int id, {
  int author = 7,
  List<dynamic> elements = const [],
}) {
  final json = storyDetail(id: id);
  json['user_id'] = author;
  json['user'] = {'id': author, 'name': 'Traveler $author', 'avatar_url': null};
  json['media'] = [
    {
      'id': 19,
      'url': 'https://example.invalid/full-$id.png',
      'thumbnail_url': null,
      'mime_type': 'image/png',
      'width': 1080,
      'height': 1920,
    },
  ];
  json['elements'] = elements;
  json['expires_at'] = DateTime.now()
      .add(const Duration(hours: 1))
      .toIso8601String();
  return json;
}

class ViewerRepo extends StoriesRepo {
  final calls = <int>[];
  @override
  Future<void> recordView(int id) async {}
  Future<StoryDetail> Function(int) handler = (id) async =>
      StoryDetail.fromJson(viewerDetail(id));
  @override
  Future<StoryDetail> getStory(int id) {
    calls.add(id);
    return handler(id);
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
    await session.saveToken('viewer-test-session');
  });
  tearDown(() async {
    await session.clear();
  });

  test(
    'loads full details by story ID, navigates loaded author order and ends without pagination',
    () async {
      final repo = ViewerRepo()
        ..handler = (id) async =>
            StoryDetail.fromJson(viewerDetail(id, author: id == 3 ? 8 : 7));
      final cubit = StoryViewerCubit(
        groups: [
          viewerGroup(7, [1, 2]),
          viewerGroup(8, [3]),
        ],
        initialAuthorId: 7,
        repo: repo,
      );
      addTearDown(cubit.close);
      await cubit.start();
      expect(repo.calls, [1]);
      expect(cubit.state.count, 2);
      await cubit.next();
      expect(cubit.state.detail!.id, 2);
      expect(cubit.state.index, 1);
      await cubit.next();
      expect(cubit.state.detail!.userId, 8);
      expect(cubit.state.count, 1);
      await cubit.previous();
      expect(cubit.state.detail!.id, 2);
      await cubit.previous();
      expect(cubit.state.detail!.id, 1);
      await cubit.next();
      await cubit.next();
      await cubit.next();
      expect(cubit.state.status, StoryViewerStatus.finished);
      expect(repo.calls, [1, 2, 3, 2, 1, 2, 3]);
    },
  );
  testWidgets(
    'timer waits for decoded photo; long press and lifecycle pause compose and resume',
    (tester) async {
      final repo = ViewerRepo();
      final cubit = StoryViewerCubit(
        groups: [
          viewerGroup(7, [1, 2]),
        ],
        initialAuthorId: 7,
        repo: repo,
      );
      await cubit.start();
      await tester.pump(const Duration(seconds: 10));
      expect(repo.calls, [1]);
      expect(cubit.state.progress, 0);
      cubit.imageDisplayed(cubit.state.request);
      await tester.pump(const Duration(seconds: 1));
      expect(cubit.state.progress, closeTo(.2, .01));
      cubit.pause(true);
      cubit.pause(true, reason: 'lifecycle');
      await tester.pump(const Duration(seconds: 10));
      expect(cubit.state.progress, closeTo(.2, .01));
      cubit.pause(false);
      await tester.pump(const Duration(seconds: 10));
      expect(repo.calls, [1, 1]);
      cubit.pause(false, reason: 'lifecycle');
      await tester.pump(const Duration(seconds: 4));
      expect(repo.calls, [1, 1, 2]);
      expect(cubit.state.imageReady, false);
      cubit.imageDisplayed(cubit.state.request);
      await tester.pump(const Duration(seconds: 5));
      expect(cubit.state.status, StoryViewerStatus.finished);
      await cubit.close();
    },
  );
  for (final code in [403, 404]) {
    test('$code blocks photo/timing and provides retry or skip', () async {
      final repo = ViewerRepo()
        ..handler = (_) async =>
            throw ApiError(message: 'denied', statusCode: code);
      final cubit = StoryViewerCubit(
        groups: [
          viewerGroup(7, [1, 2]),
        ],
        initialAuthorId: 7,
        repo: repo,
      );
      addTearDown(cubit.close);
      await cubit.start();
      expect(cubit.state.status, StoryViewerStatus.failure);
      expect(cubit.state.error!.statusCode, code);
      expect(cubit.state.detail, null);
      repo.handler = (id) async => StoryDetail.fromJson(viewerDetail(id));
      await cubit.retry();
      expect(cubit.state.detail!.id, 1);
      await cubit.next();
      expect(cubit.state.detail!.id, 2);
    });
  }
  test(
    'known expired summaries are skipped; empty or unknown initial author closes safely',
    () async {
      final repo = ViewerRepo();
      final cubit = StoryViewerCubit(
        groups: [
          viewerGroup(7, [
            1,
          ], expiry: DateTime.now().subtract(const Duration(seconds: 1))),
          viewerGroup(8, [2]),
        ],
        initialAuthorId: 7,
        repo: repo,
      );
      repo.handler = (id) async =>
          StoryDetail.fromJson(viewerDetail(id, author: 8));
      addTearDown(cubit.close);
      await cubit.start();
      expect(repo.calls, [2]);
      final empty = StoryViewerCubit(
        groups: [],
        initialAuthorId: 99,
        repo: repo,
      );
      addTearDown(empty.close);
      await empty.start();
      expect(empty.state.status, StoryViewerStatus.finished);
    },
  );
  test(
    'expired detail, missing media URL, invalid overlays and mismatched owner never render',
    () async {
      for (final kind in [
        'expired',
        'media',
        'emptyMedia',
        'overlays',
        'owner',
      ]) {
        final repo = ViewerRepo()
          ..handler = (id) async {
            final json = viewerDetail(id);
            switch (kind) {
              case 'expired':
                json['expires_at'] = '2000-01-01T00:00:00Z';
              case 'media':
                (json['media'] as List).single['url'] = null;
              case 'emptyMedia':
                json['media'] = [];
              case 'overlays':
                json['elements'] = [
                  {'version': 99},
                ];
              case 'owner':
                json['user_id'] = 8;
                json['user'] = {'id': 8, 'name': 'Other'};
            }
            return StoryDetail.fromJson(json);
          };
        final cubit = StoryViewerCubit(
          groups: [
            viewerGroup(7, [1]),
          ],
          initialAuthorId: 7,
          repo: repo,
        );
        await cubit.start();
        expect(cubit.state.status, StoryViewerStatus.failure, reason: kind);
        expect(cubit.state.detail, null);
        await cubit.close();
      }
    },
  );
  test(
    'rapid navigation discards a stale network or image completion',
    () async {
      final first = Completer<StoryDetail>();
      final repo = ViewerRepo()
        ..handler = (id) => id == 1
            ? first.future
            : Future.value(StoryDetail.fromJson(viewerDetail(id)));
      final cubit = StoryViewerCubit(
        groups: [
          viewerGroup(7, [1, 2]),
        ],
        initialAuthorId: 7,
        repo: repo,
      );
      addTearDown(cubit.close);
      final pending = cubit.start();
      final oldRequest = cubit.state.request;
      await cubit.next();
      first.complete(StoryDetail.fromJson(viewerDetail(1)));
      await pending;
      cubit.imageDisplayed(oldRequest);
      cubit.imageFailed(oldRequest);
      expect(cubit.state.detail!.id, 2);
      expect(cubit.state.imageReady, false);
    },
  );
  test(
    'session switch and disposal discard late responses and cancel playback',
    () async {
      for (final dispose in [false, true]) {
        final result = Completer<StoryDetail>();
        final repo = ViewerRepo()..handler = (_) => result.future;
        final cubit = StoryViewerCubit(
          groups: [
            viewerGroup(7, [1]),
          ],
          initialAuthorId: 7,
          repo: repo,
        );
        final pending = cubit.start();
        if (dispose) {
          await cubit.close();
        } else {
          await session.saveToken('next-viewer-session');
        }
        result.complete(StoryDetail.fromJson(viewerDetail(1)));
        await pending;
        expect(cubit.state.detail, null);
        if (!dispose) {
          expect(cubit.state.status, StoryViewerStatus.finished);
          await cubit.close();
        }
      }
    },
  );
  test(
    'blocking current author invalidates their read and advances to a loaded unblocked author',
    () async {
      final follow = FollowCubit();
      final blocks = BlockCubit(follow: follow);
      final result = Completer<StoryDetail>();
      final repo = ViewerRepo()
        ..handler = (id) => id == 1
            ? result.future
            : Future.value(StoryDetail.fromJson(viewerDetail(id, author: 8)));
      final cubit = StoryViewerCubit(
        groups: [
          viewerGroup(7, [1]),
          viewerGroup(8, [2]),
        ],
        initialAuthorId: 7,
        repo: repo,
        blocks: blocks,
      );
      final pending = cubit.start();
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      blocks.emit(BlockState(blocked: {'7': true}));
      await Future<void>.delayed(Duration.zero);
      result.complete(StoryDetail.fromJson(viewerDetail(1)));
      await pending;
      expect(cubit.state.detail!.userId, 8);
      await cubit.close();
      await blocks.close();
      await follow.close();
    },
  );
  test(
    'network-image failure stops progression and permits a clean GET retry',
    () async {
      final repo = ViewerRepo();
      final cubit = StoryViewerCubit(
        groups: [
          viewerGroup(7, [1]),
        ],
        initialAuthorId: 7,
        repo: repo,
      );
      addTearDown(cubit.close);
      await cubit.start();
      cubit.imageFailed(cubit.state.request);
      expect(cubit.state.status, StoryViewerStatus.failure);
      expect(cubit.state.detail, null);
      await cubit.retry();
      expect(cubit.state.status, StoryViewerStatus.ready);
      expect(repo.calls, [1, 1]);
    },
  );

  final photo = MemoryImage(photoBytes());
  Future<void> open(
    WidgetTester tester,
    ViewerRepo repo, {
    List<StoryGroup>? groups,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => StoryViewerScreen(
                    groups:
                        groups ??
                        [
                          viewerGroup(7, [1, 2]),
                        ],
                    initialAuthorId: 7,
                    repo: repo,
                    imageProvider: (_) => photo,
                  ),
                ),
              ),
              child: const Text('Open viewer'),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => precacheImage(photo, tester.element(find.byType(TextButton))),
    );
    await tester.tap(find.text('Open viewer'));
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
  }

  testWidgets(
    'viewer renders full image and overlays with editor geometry and no editing controls',
    (tester) async {
      const layer = StoryTextLayer(
        id: 'text',
        text: 'Travibe',
        center: Offset(.4, .65),
        scale: 1.4,
      );
      final repo = ViewerRepo()
        ..handler = (id) async => StoryDetail.fromJson(
          viewerDetail(id, elements: StoryElements.encode([layer])),
        );
      await open(tester, repo);
      expect(find.byType(StoryViewerCanvas), findsOneWidget);
      expect(find.byKey(const ValueKey('story-delete-target')), findsNothing);
      final canvasSize = tester.getSize(find.byType(StoryViewerCanvas));
      final geometry = StoryTextGeometry(layer, canvasSize);
      final positioned = tester.widget<Positioned>(
        find.byKey(const ValueKey('story-viewer-layer-text')),
      );
      final scale = geometry.fitScale(layer.scale);
      final center = geometry.bound(layer.center, scale, canvasSize);
      expect(
        positioned.left,
        closeTo(center.dx * canvasSize.width - geometry.size.width / 2, .001),
      );
      expect(
        positioned.top,
        closeTo(center.dy * canvasSize.height - geometry.size.height / 2, .001),
      );
      final rich = tester.widget<RichText>(
        find.descendant(
          of: find.byKey(const ValueKey('story-viewer-layer-text')),
          matching: find.byType(RichText),
        ),
      );
      expect(rich.text.style, geometry.style);
      expect(
        tester
            .widget<Image>(find.byKey(const ValueKey('story-viewer-photo')))
            .fit,
        BoxFit.cover,
      );
      expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
      expect(repo.calls, [1, 1]);
      await tester.tap(find.byKey(const ValueKey('story-viewer-close')));
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'tap navigation, long press pause and auto-close use only loaded stories',
    (tester) async {
      final repo = ViewerRepo();
      await open(tester, repo);
      final taps = find.byKey(const ValueKey('story-viewer-taps'));
      final rect = tester.getRect(taps);
      final gesture = await tester.startGesture(rect.center);
      await tester.pump(const Duration(milliseconds: 600));
      final before = tester
          .widget<LinearProgressIndicator>(
            find.byKey(const ValueKey('story-progress-0')),
          )
          .value;
      await tester.pump(const Duration(seconds: 6));
      expect(repo.calls, [1, 1]);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const ValueKey('story-progress-0')),
            )
            .value,
        before,
      );
      await gesture.up();
      await tester.pump();
      await tester.tapAt(Offset(rect.right - 20, rect.center.dy));
      await tester.pump();
      await tester.pump();
      expect(repo.calls, [1, 1, 2, 2]);
      await tester.tapAt(Offset(rect.left + 20, rect.center.dy));
      await tester.pump();
      await tester.pump();
      expect(repo.calls, [1, 1, 2, 2, 1]);
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      await tester.pump();
      expect(repo.calls.last, 2);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.byType(StoryViewerScreen), findsNothing);
    },
  );
  testWidgets(
    'loading, error/retry and skip never substitute a thumbnail for full details',
    (tester) async {
      final pending = Completer<StoryDetail>();
      final repo = ViewerRepo()..handler = (_) => pending.future;
      // Avoid settling the indeterminate spinner while the request is unresolved.
      await tester.pumpWidget(
        MaterialApp(
          home: StoryViewerScreen(
            groups: [
              viewerGroup(7, [1]),
            ],
            initialAuthorId: 7,
            repo: repo,
            imageProvider: (_) => photo,
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      pending.completeError(ApiError(message: 'offline'));
      await tester.pump();
      await tester.pump();
      expect(find.text('offline'), findsOneWidget);
      expect(find.byType(StoryViewerCanvas), findsNothing);
      repo.handler = (id) async => StoryDetail.fromJson(viewerDetail(id));
      await tester.tap(find.byKey(const ValueKey('story-viewer-retry')));
      await tester.pump();
      await tester.pump();
      expect(repo.calls, [1, 1, 1]);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'closing stops playback immediately and cannot pop the underlying Home route twice',
    (tester) async {
      final repo = ViewerRepo();
      await open(tester, repo);
      await tester.tap(find.byKey(const ValueKey('story-viewer-close')));
      await tester.tap(
        find.byKey(const ValueKey('story-viewer-close')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 20));
      await tester.pump(const Duration(seconds: 6));
      expect(find.text('Open viewer'), findsOneWidget);
      expect(find.byType(StoryViewerScreen), findsNothing);
      expect(repo.calls, [1, 1]);
    },
  );
  testWidgets(
    'account switching closes the viewer and clears the visible photo',
    (tester) async {
      await open(tester, ViewerRepo());
      expect(find.byType(StoryViewerCanvas), findsOneWidget);
      await session.saveToken('switched-widget-viewer-session');
      await tester.pumpAndSettle(const Duration(milliseconds: 20));
      expect(find.byType(StoryViewerScreen), findsNothing);
      expect(find.byType(StoryViewerCanvas), findsNothing);
    },
  );
  testWidgets(
    'cancelled long press resumes without defeating app background pause',
    (tester) async {
      final repo = ViewerRepo();
      await open(tester, repo);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('story-viewer-taps'))),
      );
      await tester.pump(const Duration(milliseconds: 600));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await gesture.cancel();
      await tester.pump(const Duration(seconds: 6));
      expect(repo.calls, [1, 1]);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      await tester.pump();
      expect(repo.calls, [1, 1, 2, 2]);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Home bubbles and own popup route to one real viewer using displayed author order',
    (tester) async {
      final adapter = StoryAdapter()
        ..handler = (request) async {
          if (request.method == 'POST' && request.path.endsWith('/view')) {
            return response({
              'data': {'views_count': 0, 'viewed_at': '2026-10-21T13:00:00Z'},
            });
          }
          final id = int.parse(request.path.split('/').last);
          return response({'data': viewerDetail(id, author: id == 2 ? 8 : 7)});
        };
      final repo = repository(adapter);
      final loadedUrls = <String>[];
      final selectedAuthors = <int>[];
      final orders = <List<int>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: HomeStories(
                stories: [
                  viewerGroup(8, [2]),
                  viewerGroup(7, [1]),
                ],
                currentUserId: 7,
                onViewStory: (groups, author) {
                  selectedAuthors.add(author);
                  orders.add(groups.map((g) => g.user.id).toList());
                  Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => StoryViewerScreen(
                        groups: groups,
                        initialAuthorId: author,
                        repo: repo,
                        imageProvider: (url) {
                          loadedUrls.add(url);
                          return photo;
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => precacheImage(photo, tester.element(find.byType(HomeStories))),
      );
      await tester.tap(find.byKey(const ValueKey('your-story-bubble')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MenuItemButton>(find.byKey(const ValueKey('view-my-story')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const ValueKey('view-my-story')));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pumpAndSettle(const Duration(milliseconds: 20));
      expect(find.byType(StoryViewerScreen), findsOneWidget);
      expect(selectedAuthors, [7]);
      expect(orders.single, [7, 8]);
      expect(
        adapter.requests.where((r) => r.method == 'GET').first.path,
        'stories/1',
      );
      expect(
        adapter.requests.where((r) => r.method == 'GET').first.method,
        'GET',
      );
      await tester.tap(find.byKey(const ValueKey('story-viewer-close')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('story-author-8')));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pumpAndSettle(const Duration(milliseconds: 20));
      expect(selectedAuthors, [7, 8]);
      expect(loadedUrls, [
        'https://example.invalid/full-1.png',
        'https://example.invalid/full-2.png',
      ]);
      expect(
        adapter.requests.where((r) => r.method == 'GET').last.path,
        'stories/2',
      );
      expect(
        adapter.requests.every(
          (r) =>
              r.method == 'GET' ||
              (r.method == 'POST' &&
                  r.path.endsWith('/view') &&
                  r.data == null),
        ),
        true,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
