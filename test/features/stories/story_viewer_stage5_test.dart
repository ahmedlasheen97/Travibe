import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/stories/cubit/stories_cubit.dart';
import 'package:travibe/features/stories/cubit/story_viewer_cubit.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/screens/story_viewer_screen.dart';
import 'package:travibe/features/stories/widgets/story_viewer_canvas.dart';
import 'fixtures.dart';
import 'story_publishing_test.dart'
    show StoryAdapter, repository, response, pageJson, groupJson;
import 'story_viewer_test.dart' show viewerGroup, viewerDetail;

class TrackingRepo extends StoriesRepo {
  int views = 0, reads = 0;
  Future<void> Function()? onView;
  Future<StoryDetail> Function(int id, int read)? onRead;
  @override
  Future<void> recordView(int id) async {
    views++;
    await onView?.call();
  }

  @override
  Future<StoryDetail> getStory(int id) async {
    reads++;
    return onRead != null
        ? onRead!(id, reads)
        : fullStory(id, count: reads > 1 ? 6 : 4);
  }
}

StoryDetail fullStory(
  int id, {
  int count = 4,
  int author = 7,
  DateTime? createdAt,
}) {
  final json = viewerDetail(id, author: author)..['views_count'] = count;
  json['created_at'] = createdAt?.toUtc().toIso8601String();
  return StoryDetail.fromJson(json);
}

class GroupRepo extends StoriesRepo {
  Future<StoriesPage> Function()? handler;
  @override
  Future<StoriesPage> getStories({int page = 1}) => handler!();
}

void main() {
  final session = PreferencesManager();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await session.init();
    await session.saveToken('stage5-test-session');
  });
  tearDown(() async => session.clear());
  StoryViewerCubit viewer(
    StoriesRepo repo, {
    void Function(int, int)? viewed,
  }) => StoryViewerCubit(
    groups: [
      viewerGroup(7, [1, 2]),
    ],
    initialAuthorId: 7,
    repo: repo,
    onViewed: viewed,
  );

  for (final body in [
    null,
    {'message': 'acknowledged'},
    {'anything': []},
    'not JSON',
  ]) {
    test(
      'view accepts successful unverified body $body without parsing fields',
      () async {
        final adapter = StoryAdapter()
          ..handler = (_) async => ResponseBody.fromString(
            body is String ? body : '$body',
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        await repository(adapter).recordView(1);
        expect(adapter.requests.single.method, 'POST');
        expect(adapter.requests.single.path, 'stories/1/view');
        expect(adapter.requests.single.data, isNull);
        expect(adapter.requests.single.responseType, ResponseType.plain);
      },
    );
  }
  test(
    'shared repository deduplicates concurrent views and allows a later repeat',
    () async {
      final pending = Completer<void>();
      final started = Completer<void>();
      final adapter = StoryAdapter()
        ..handler = (_) async {
          if (!started.isCompleted) started.complete();
          await pending.future;
          return response(null);
        };
      final repo = repository(adapter);
      final first = repo.recordView(1);
      final second = repo.recordView(1);
      expect(identical(first, second), true);
      await started.future;
      expect(adapter.requests, hasLength(1));
      pending.complete();
      await Future.wait([first, second]);
      await repo.recordView(1);
      expect(adapter.requests, hasLength(2));
    },
  );
  test(
    'shared view guard never reuses another accounts in-flight request',
    () async {
      final pending = Completer<void>();
      final firstStarted = Completer<void>();
      final bothStarted = Completer<void>();
      var started = 0;
      final adapter = StoryAdapter()
        ..handler = (_) async {
          started++;
          if (started == 1) firstStarted.complete();
          if (started == 2) bothStarted.complete();
          await pending.future;
          return response(null);
        };
      final repo = repository(adapter);
      final first = repo.recordView(1);
      await firstStarted.future;
      await session.saveToken('another-account-view-request');
      final second = repo.recordView(1);
      expect(identical(first, second), false);
      await bothStarted.future;
      expect(adapter.requests, hasLength(2));
      pending.complete();
      await Future.wait([first, second]);
    },
  );
  test(
    'opening starts at selected author first unseen; all-seen falls back to first',
    () async {
      final repo = TrackingRepo()
        ..onRead = (id, _) async => fullStory(id, author: 8);
      final group = viewerGroup(8, [11, 12, 13]).reconcile({11: 2}, {});
      final cubit = StoryViewerCubit(
        groups: [
          viewerGroup(7, [1]),
          group,
        ],
        initialAuthorId: 8,
        repo: repo,
      );
      await cubit.start();
      expect(cubit.state.detail!.id, 12);
      expect(cubit.state.detail!.userId, 8);
      expect(cubit.state.index, 1);
      expect(cubit.state.count, 3);
      await cubit.previous();
      expect(cubit.state.detail!.id, 11);
      await cubit.close();
      final allSeen = StoryViewerCubit(
        groups: [
          group.reconcile({12: 2, 13: 2}, {}),
        ],
        initialAuthorId: 8,
        repo: repo,
      );
      await allSeen.start();
      expect(allSeen.state.detail!.id, 11);
      await allSeen.close();
    },
  );
  test(
    'expired unseen is not preferred over an accessible seen story',
    () async {
      final json = groupJson(7);
      json['stories'] = [
        {
          'id': 1,
          'thumbnail_url': null,
          'created_at': null,
          'expires_at': DateTime.now()
              .subtract(const Duration(hours: 1))
              .toIso8601String(),
          'views_count': 2,
          'has_seen': false,
        },
        {
          'id': 2,
          'thumbnail_url': null,
          'created_at': null,
          'expires_at': DateTime.now()
              .add(const Duration(hours: 1))
              .toIso8601String(),
          'views_count': 3,
          'has_seen': true,
        },
      ];
      final cubit = StoryViewerCubit(
        groups: [StoryGroup.fromJson(json)],
        initialAuthorId: 7,
        repo: TrackingRepo(),
      );
      await cubit.start();
      expect(cubit.state.detail!.id, 2);
      expect(cubit.state.count, 1);
      await cubit.close();
    },
  );
  test(
    'confirmed POST then documented detail GET reconciles count without local increment',
    () async {
      final ack = Completer<void>();
      final fresh = Completer<StoryDetail>();
      final repo = TrackingRepo()
        ..onView = (() => ack.future)
        ..onRead = ((id, read) async =>
            read == 1 ? fullStory(id) : fresh.future);
      final counts = <int>[];
      final cubit = viewer(repo, viewed: (_, count) => counts.add(count));
      await cubit.start();
      cubit.imageDisplayed(cubit.state.request);
      expect(repo.views, 1);
      expect(counts, isEmpty);
      ack.complete();
      await Future<void>.delayed(Duration.zero);
      expect(counts, [4]);
      expect(cubit.state.viewsCount, isNull);
      cubit.pause(true);
      cubit.pause(false);
      expect(repo.views, 1);
      fresh.complete(fullStory(1, count: 6));
      await Future<void>.delayed(Duration.zero);
      expect(counts, [4, 6]);
      expect(cubit.state.viewsCount, 6);
      expect(repo.views, 1);
      await cubit.close();
    },
  );
  test(
    'real repository POST body is ignored and GET count used end to end',
    () async {
      var adapterCount = 4;
      final adapter = StoryAdapter()
        ..handler = (request) async {
          if (request.method == 'POST') return response({'unverified': 'ack'});
          final json = viewerDetail(1)..['views_count'] = adapterCount;
          return response({'data': json});
        };
      // This test uses response values, not a locally computed increment.
      final confirmed = Completer<void>();
      final cubit = viewer(
        repository(adapter),
        viewed: (_, count) {
          if (count == 9) confirmed.complete();
        },
      );
      await cubit.start();
      adapterCount = 9;
      cubit.imageDisplayed(cubit.state.request);
      await confirmed.future;
      expect(adapter.requests.map((r) => r.method), ['GET', 'POST', 'GET']);
      expect(cubit.state.viewsCount, 9);
      await cubit.close();
    },
  );
  test(
    'failed count refresh preserves playback and never repeats a successful POST',
    () async {
      final repo = TrackingRepo()
        ..onRead = (id, read) async {
          if (read == 2) throw ApiError(message: 'Offline');
          return fullStory(id);
        };
      final counts = <int>[];
      final cubit = viewer(repo, viewed: (_, count) => counts.add(count));
      await cubit.start();
      cubit.imageDisplayed(cubit.state.request);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.status, StoryViewerStatus.ready);
      expect(counts, [4]);
      cubit.pause(true);
      cubit.pause(false);
      await cubit.previous();
      cubit.imageDisplayed(cubit.state.request);
      await Future<void>.delayed(Duration.zero);
      expect(repo.views, 1);
      await cubit.close();
    },
  );
  for (final code in [401, 403, 404]) {
    for (final failOnPost in [true, false]) {
      test(
        '$code during ${failOnPost ? 'view POST' : 'count GET'} clears inaccessible content',
        () async {
          final repo = TrackingRepo();
          if (failOnPost) {
            repo.onView = () async =>
                throw ApiError(message: 'Denied', statusCode: code);
          } else {
            repo.onRead = (id, read) async {
              if (read > 1) throw ApiError(message: 'Denied', statusCode: code);
              return fullStory(id);
            };
          }
          final cubit = viewer(repo);
          await cubit.start();
          cubit.imageDisplayed(cubit.state.request);
          await Future<void>.delayed(Duration.zero);
          expect(cubit.state.status, StoryViewerStatus.failure);
          expect(cubit.state.detail, isNull);
          expect(cubit.state.error!.statusCode, code);
          expect(cubit.state.layers, isEmpty);
          await cubit.close();
        },
      );
    }
  }
  test(
    'reopening repeats view recording without increasing the count locally',
    () async {
      final repo = TrackingRepo()
        ..onRead = (id, _) async => fullStory(id, count: 5);
      final counts = <int>[];
      for (var visit = 0; visit < 2; visit++) {
        final cubit = viewer(repo, viewed: (_, count) => counts.add(count));
        await cubit.start();
        cubit.imageDisplayed(cubit.state.request);
        await Future<void>.delayed(Duration.zero);
        expect(cubit.state.viewsCount, 5);
        await cubit.close();
      }
      expect(repo.views, 2);
      expect(counts, [5, 5, 5, 5]);
    },
  );
  test('account switch drops stale count reconciliation', () async {
    final fresh = Completer<StoryDetail>();
    final repo = TrackingRepo()
      ..onRead = ((id, read) async => read == 1 ? fullStory(id) : fresh.future);
    final counts = <int>[];
    final cubit = viewer(repo, viewed: (_, count) => counts.add(count));
    await cubit.start();
    cubit.imageDisplayed(cubit.state.request);
    await Future<void>.delayed(Duration.zero);
    await session.saveToken('another-stage5-account');
    fresh.complete(fullStory(1, count: 999));
    await Future<void>.delayed(Duration.zero);
    expect(counts, [4]);
    expect(cubit.state.status, StoryViewerStatus.finished);
    await cubit.close();
  });
  test(
    'a disposed viewers late count GET cannot overwrite a newer Home count',
    () async {
      final fresh = Completer<StoryDetail>();
      final repo = TrackingRepo()
        ..onRead = ((id, read) async =>
            read == 1 ? fullStory(id) : fresh.future);
      final counts = <int>[];
      final cubit = viewer(repo, viewed: (_, count) => counts.add(count));
      await cubit.start();
      cubit.imageDisplayed(cubit.state.request);
      await Future<void>.delayed(Duration.zero);
      expect(counts, [4]);
      await cubit.close();
      fresh.complete(fullStory(1, count: 999));
      await Future<void>.delayed(Duration.zero);
      expect(counts, [4]);
      expect(repo.views, 1);
    },
  );
  test(
    'disposal before view acknowledgement prevents another network read',
    () async {
      final ack = Completer<void>();
      final repo = TrackingRepo()..onView = (() => ack.future);
      final cubit = viewer(repo);
      await cubit.start();
      cubit.imageDisplayed(cubit.state.request);
      await cubit.close();
      ack.complete();
      await Future<void>.delayed(Duration.zero);
      expect(repo.views, 1);
      expect(repo.reads, 1);
    },
  );
  test(
    'fresh Home counts replace cached values without stale reads undoing a view',
    () async {
      var count = 2;
      StoriesPage page() => StoriesPage.fromJson(
        pageJson([
          groupJson(7, storyId: 1)..['stories'][0]['views_count'] = count,
        ]),
      );
      final repo = GroupRepo()..handler = (() async => page());
      final home = StoriesCubit(repo: repo);
      await home.load();
      home.confirmedView(1, 4);
      count = 9;
      await home.refresh();
      expect(home.state.groups.single.stories.single.viewsCount, 9);
      home.confirmedView(2, 0);
      expect(home.state.groups.single.stories.single.viewsCount, 9);
      final late = Completer<StoriesPage>();
      repo.handler = () => late.future;
      final stale = home.refresh();
      home.confirmedView(1, 12);
      late.complete(page());
      await stale;
      expect(home.state.groups.single.stories.single.viewsCount, 12);
      expect(home.state.groups.single.hasUnseen, false);
      await home.close();
    },
  );
  testWidgets('header shows real posting time and omits missing date', (
    tester,
  ) async {
    final photo = MemoryImage(photoBytes());
    for (final createdAt in [
      DateTime.now().subtract(const Duration(hours: 2)),
      null,
    ]) {
      final repo = TrackingRepo()
        ..onRead = (id, _) async => fullStory(id, createdAt: createdAt);
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
      await tester.runAsync(
        () => precacheImage(
          photo,
          tester.element(find.byType(StoryViewerScreen)),
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 20));
      expect(find.byType(StoryViewerCanvas), findsOneWidget);
      if (createdAt == null) {
        expect(find.byKey(const ValueKey('story-posting-time')), findsNothing);
      } else {
        expect(find.text('2h'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
