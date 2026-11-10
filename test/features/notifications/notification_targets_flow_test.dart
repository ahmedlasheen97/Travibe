import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/notifications/data/notification_diagnostics.dart';
import 'package:travibe/features/notifications/data/notification_model.dart';
import 'package:travibe/features/notifications/data/notification_targets.dart';
import 'package:travibe/features/notifications/data/notification_presentation.dart';
import 'package:travibe/features/notifications/cubit/notification_activity.dart';
import 'package:travibe/features/notifications/screens/notifications_screen.dart';
import 'package:travibe/features/notifications/screens/notification_navigation.dart';
import 'package:travibe/features/notifications/screens/notification_post_screen.dart';
import 'package:travibe/features/notifications/widgets/notification_row.dart';
import 'package:travibe/features/comments/screens/comments_screen.dart';
import 'package:travibe/features/chats/screens/conversation_screen.dart';
import 'package:travibe/features/chats/widgets/chat_composer.dart';
import 'package:travibe/features/chats/widgets/chat_request_controls.dart';
import 'package:travibe/features/profile/screens/profile_screen.dart';
import 'package:travibe/features/stories/screens/story_viewer_screen.dart';
import '../profile/profile_posts_fixtures.dart'
    show authorPostJson, AuthorProfilesRepo, AuthorPostsRepo;
import '../stories/story_viewer_test.dart' show viewerDetail, ViewerRepo;
import '../comments/fixtures.dart' show commentJson, MemoryCommentsRepo;
import '../chats/message_requests_test.dart' show RequestsRepo;
import 'notifications_screen_test.dart' show InboxRepo, app;

Map<String, dynamic> notice(
  String type, {
  String id = 'n1',
  String? morph,
  int? target,
  Map<String, dynamic> data = const {},
  bool read = false,
}) => {
  'id': id,
  'type': type,
  'target_type': morph,
  'target_id': target,
  'actor': {'id': 7, 'name': 'Fixture actor', 'is_blocked': false},
  'data': data,
  'read_at': read ? '2026-11-09T00:00:00Z' : null,
  'created_at': '2026-11-09T00:00:00Z',
};

class TargetAdapter implements HttpClientAdapter {
  final calls = <RequestOptions>[];
  final Map<String, Object?> values = {};
  Completer<void>? gate;
  int active = 0, maxActive = 0, status = 200;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options);
    active++;
    if (active > maxActive) maxActive = active;
    final data = jsonEncode(values[options.path]);
    try {
      if (gate != null) await gate!.future;
      return ResponseBody.fromString(
        data,
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    } finally {
      active--;
    }
  }

  @override
  void close({bool force = false}) {}
}

class ReadingRepo extends InboxRepo {
  int allWrites = 0;
  bool failWrite = false;
  Completer<void>? writeGate;
  @override
  Future<void> markAllRead() async {
    allWrites++;
    if (failWrite) throw ApiError(message: 'Read failed');
    // Server commits before its delayed response; subsequent arrivals stay unread.
    items = [
      for (final item in items)
        {...item, 'read_at': DateTime.now().toIso8601String()},
    ];
    if (writeGate != null) await writeGate!.future;
  }
}

void main() {
  final preferences = PreferencesManager();
  late TargetAdapter adapter;
  late NotificationTargetsRepository targets;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'_token': 'fixture-session'});
    await preferences.init();
    adapter = TargetAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://fixtures.invalid/api/v1/'))
      ..httpClientAdapter = adapter;
    targets = NotificationTargetsRepository(
      dio: dio,
      maxConcurrent: 2,
      chats: RequestsRepo(),
    );
    adapter.values['posts/10'] = {
      'data': authorPostJson(10, 7)..['media'] = [],
    };
    adapter.values['stories/30'] = {'data': viewerDetail(30)};
    adapter.values['posts/10/comments/9'] = {
      'data': commentJson(9)..['post_id'] = 10,
    };
  });
  tearDown(() async {
    targets.dispose();
    await preferences.clear();
  });

  test(
    'unknown diagnostics deduplicate and disclose no raw type, payload, IDs or URL',
    () {
      final logs = <String>[];
      final diagnostics = NotificationDiagnostics(log: logs.add);
      final item = InboxNotification.fromJson(
        notice(
          'private-type-secret',
          target: 987654321,
          data: {'body': 'private message', 'token': 'private token'},
        ),
      );
      diagnostics.inspect(item);
      diagnostics.inspect(item);
      expect(logs, hasLength(1));
      for (final secret in [
        'private-type-secret',
        'private message',
        'private token',
        '987654321',
      ]) {
        expect(logs.single.contains(secret), false);
      }
      diagnostics.inspect(InboxNotification.fromJson(notice('story_liked')));
      expect(logs, hasLength(1));
      NotificationDiagnostics(log: logs.add, enabled: false).inspect(item);
      expect(logs, hasLength(1));
    },
  );

  test(
    'documented target relationships ignore arbitrary routes and missing comment parent IDs',
    () {
      NotificationTarget? resolve(
        String type,
        String? morph, {
        Map<String, dynamic> data = const {},
      }) => NotificationTarget.from(
        InboxNotification.fromJson(
          notice(type, morph: morph, target: 10, data: data),
        ),
      );
      expect(
        resolve('post_liked', r'App\Models\Post')!.kind,
        NotificationTargetKind.post,
      );
      expect(
        resolve('story_liked', r'App\Models\Story')!.kind,
        NotificationTargetKind.story,
      );
      expect(
        resolve(
          'comment_liked',
          r'App\Models\Comment',
          data: {'post_id': 10},
        )!.postId,
        10,
      );
      expect(resolve('comment_replied', r'App\Models\Comment'), isNull);
      expect(
        resolve('user_mentioned', r'App\Models\Story')!.kind,
        NotificationTargetKind.story,
      );
      expect(resolve('user_followed', null)!.id, 7);
      expect(
        resolve(
          'message_received',
          null,
          data: {'conversation_id': 42, 'route': 'https://unsafe'},
        )!.id,
        42,
      );
      expect(
        resolve('message_received', null, data: {'route': '/chat/42'}),
        isNull,
      );
      expect(resolve('unknown', r'App\Models\Post'), isNull);
      expect(resolve('story_liked', r'App\Models\Post'), isNull);
    },
  );

  test(
    'authorized post lookups deduplicate, select first real image, and omit text-only media',
    () async {
      const target = NotificationTarget(NotificationTargetKind.post, 10);
      final text = await targets.resolve(target);
      expect(text.thumbnail, isNull);
      adapter.values['posts/10'] = {
        'data': authorPostJson(10, 7)
          ..['media'] = [
            {
              'id': 1,
              'url': 'https://fixtures.invalid/first.png',
              'mime_type': 'image/png',
            },
            {
              'id': 2,
              'url': 'https://fixtures.invalid/second.jpg',
              'mime_type': 'image/jpeg',
            },
          ],
      };
      targets.invalidate();
      adapter.gate = Completer();
      final first = targets.resolve(target),
          second = targets.resolve(target),
          fresh = targets.resolve(target, fresh: true);
      expect(identical(first, second), true);
      expect(identical(first, fresh), true);
      adapter.gate!.complete();
      expect(
        (await first).thumbnail!.url,
        'https://fixtures.invalid/first.png',
      );
      expect(adapter.calls.length, 2);
      expect(
        adapter.calls.every(
          (call) =>
              call.method == 'GET' &&
              call.extra['sessionRevision'] == preferences.sessionRevision,
        ),
        true,
      );
    },
  );

  test(
    'story preview uses authorized detail and expired stories are rejected',
    () async {
      const target = NotificationTarget(NotificationTargetKind.story, 30);
      final value = await targets.resolve(target);
      expect(value.thumbnail!.kind, NotificationMediaKind.story);
      adapter.values['stories/30'] = {
        'data': viewerDetail(30)..['expires_at'] = '2000-01-01T00:00:00Z',
      };
      await expectLater(
        targets.resolve(target, fresh: true),
        throwsA(isA<ApiError>()),
      );
    },
  );

  test(
    'comment detail validates relationship and shares cached post lookup',
    () async {
      await targets.resolve(
        const NotificationTarget(NotificationTargetKind.post, 10),
      );
      final comment = await targets.resolve(
        const NotificationTarget(NotificationTargetKind.comment, 9, postId: 10),
      );
      expect(comment.comment!.postId, 10);
      expect(adapter.calls.map((call) => call.path), [
        'posts/10',
        'posts/10/comments/9',
      ]);
      adapter.values['posts/10/comments/9'] = {
        'data': commentJson(9)..['post_id'] = 99,
      };
      await expectLater(
        targets.resolve(
          const NotificationTarget(
            NotificationTargetKind.comment,
            9,
            postId: 10,
          ),
          fresh: true,
        ),
        throwsA(isA<ApiError>()),
      );
    },
  );

  for (final status in [401, 403, 404]) {
    test(
      'inaccessible target HTTP $status is not turned into media or a fake destination',
      () async {
        adapter.status = status;
        await expectLater(
          targets.resolve(
            const NotificationTarget(NotificationTargetKind.post, 10),
          ),
          throwsA(anything),
        );
      },
    );
  }

  test(
    'concurrent target details are bounded and old-account responses cannot enter new cache',
    () async {
      adapter.gate = Completer();
      for (var id = 10; id < 14; id++) {
        adapter.values['posts/$id'] = {'data': authorPostJson(id, 7)};
      }
      final futures = [
        for (var id = 10; id < 14; id++)
          targets.resolve(NotificationTarget(NotificationTargetKind.post, id)),
      ];
      await Future<void>.delayed(Duration.zero);
      expect(adapter.maxActive, lessThanOrEqualTo(2));
      adapter.gate!.complete();
      await Future.wait(futures);
      expect(adapter.maxActive, lessThanOrEqualTo(2));
      targets.invalidate();
      adapter.gate = Completer();
      final old = targets.resolve(
        const NotificationTarget(NotificationTargetKind.post, 10),
      );
      final oldError = expectLater(old, throwsA(anything));
      await Future<void>.delayed(Duration.zero);
      await preferences.saveToken('replacement');
      adapter.gate!.complete();
      await oldError;
      adapter.gate = null;
      adapter.values['posts/10'] = {'data': authorPostJson(10, 8)};
      expect(
        (await targets.resolve(
          const NotificationTarget(NotificationTargetKind.post, 10),
        )).post!.userId,
        '8',
      );
    },
  );

  testWidgets(
    'successful load automatically reads all, resets shared badge and preserves rows without repeat writes',
    (tester) async {
      final repo = ReadingRepo()..items = [notice('user_mentioned')];
      final activity = NotificationActivity(repo: repo);
      await activity.refresh();
      expect(activity.count, 1);
      await tester.pumpWidget(
        app(
          NotificationsScreen(repo: repo, activity: activity, targets: targets),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.allWrites, 1);
      expect(activity.count, 0);
      expect(
        find.byKey(const ValueKey('notification-unread-n1')),
        findsNothing,
      );
      expect(find.byType(NotificationRow), findsOneWidget);
      activity.invalidateFromRealtime();
      await tester.pumpAndSettle();
      expect(repo.allWrites, 1);
      await tester.pumpWidget(const SizedBox());
      activity.dispose();
    },
  );

  testWidgets(
    'read-all failure keeps unread state and explicit retry confirms it',
    (tester) async {
      final repo = ReadingRepo()
        ..items = [notice('user_mentioned')]
        ..failWrite = true;
      final activity = NotificationActivity(repo: repo);
      await tester.pumpWidget(
        app(
          NotificationsScreen(repo: repo, activity: activity, targets: targets),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.allWrites, 1);
      expect(activity.count, 1);
      expect(
        find.byKey(const ValueKey('notification-unread-n1')),
        findsOneWidget,
      );
      repo.failWrite = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(repo.allWrites, 2);
      expect(activity.count, 0);
      expect(
        find.byKey(const ValueKey('notification-unread-n1')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      activity.dispose();
    },
  );

  testWidgets(
    'failed list load never sends read-all merely because unread count exists',
    (tester) async {
      final repo = ReadingRepo()
        ..items = [notice('user_mentioned')]
        ..fail = true;
      final activity = NotificationActivity(repo: repo);
      await tester.pumpWidget(
        app(
          NotificationsScreen(repo: repo, activity: activity, targets: targets),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.allWrites, 0);
      expect(activity.count, 1);
      await tester.pumpWidget(const SizedBox());
      activity.dispose();
    },
  );

  for (final sameId in [false, true]) {
    testWidgets(
      'new/reopened notification during read-all is reconciled safely; sameId=$sameId',
      (tester) async {
        final repo = ReadingRepo()
          ..items = [notice('user_mentioned')]
          ..writeGate = Completer();
        final activity = NotificationActivity(repo: repo);
        await tester.pumpWidget(
          app(
            NotificationsScreen(
              repo: repo,
              activity: activity,
              targets: targets,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(repo.allWrites, 1);
        final id = sameId ? 'n1' : 'n2';
        repo.items = [
          if (!sameId) ...repo.items,
          notice('user_mentioned', id: id),
        ];
        activity.invalidateFromRealtime(reopenedId: id);
        await tester.pumpAndSettle();
        expect(activity.count, 1);
        repo.writeGate!.complete();
        await tester.pumpAndSettle();
        expect(repo.allWrites, 2);
        expect(activity.count, 0);
        expect(find.byKey(ValueKey('notification-unread-$id')), findsNothing);
        await tester.pumpWidget(const SizedBox());
        activity.dispose();
      },
    );
  }

  testWidgets(
    'late old-session read-all cannot acknowledge a replacement account',
    (tester) async {
      final repo = ReadingRepo()
        ..items = [notice('user_mentioned')]
        ..writeGate = Completer();
      final activity = NotificationActivity(repo: repo);
      await tester.pumpWidget(
        app(
          NotificationsScreen(repo: repo, activity: activity, targets: targets),
        ),
      );
      await tester.pumpAndSettle();
      repo.items = [];
      await preferences.saveToken('replacement');
      await tester.pumpAndSettle();
      repo.writeGate!.complete();
      await tester.pumpAndSettle();
      expect(activity.count, 0);
      expect(find.byType(NotificationRow), findsNothing);
      expect(find.text('No notifications yet.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      activity.dispose();
    },
  );

  for (final type in [
    'post_liked',
    'post_commented',
    'comment_replied',
    'story_liked',
    'user_followed',
    'message_received',
    'user_mentioned',
  ]) {
    testWidgets(
      '$type uses existing content screen and returns to Notifications',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final story = type == 'story_liked',
            comment = type == 'comment_replied',
            message = type == 'message_received',
            follow = type == 'user_followed';
        final repo = ReadingRepo()
          ..items = [
            notice(
              type,
              morph: story
                  ? r'App\Models\Story'
                  : comment
                  ? r'App\Models\Comment'
                  : r'App\Models\Post',
              target: story
                  ? 30
                  : comment
                  ? 9
                  : 10,
              data: message
                  ? {'conversation_id': 42}
                  : comment
                  ? {'post_id': 10}
                  : {},
            ),
          ];
        final chat = RequestsRepo();
        final activity = NotificationActivity(repo: repo);
        await tester.pumpWidget(
          app(
            NotificationsScreen(
              repo: repo,
              activity: activity,
              targets: targets,
              openDestination: (context, item, content) =>
                  openNotificationDestination(
                    context,
                    item,
                    content,
                    stories: ViewerRepo(),
                    chats: chat,
                    comments: MemoryCommentsRepo(),
                    profiles: AuthorProfilesRepo(),
                    posts: AuthorPostsRepo(),
                  ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('notification-n1')));
        await tester.pumpAndSettle();
        final screen = story
            ? find.byType(StoryViewerScreen)
            : message
            ? find.byType(ConversationScreen)
            : follow
            ? find.byType(ProfileScreen)
            : find.byType(NotificationPostScreen);
        expect(screen, findsOneWidget);
        if (message) {
          expect(find.byType(ChatPendingRequestControls), findsOneWidget);
          expect(find.byType(ChatComposer), findsNothing);
        }
        if (type == 'post_commented' || comment) {
          expect(find.byType(CommentsScreen), findsOneWidget);
          Navigator.of(tester.element(find.byType(CommentsScreen))).pop();
          await tester.pumpAndSettle();
        }
        Navigator.of(tester.element(screen)).pop();
        await tester.pumpAndSettle();
        expect(find.byType(NotificationsScreen), findsOneWidget);
        expect(activity.count, 0);
        expect(repo.allWrites, 1);
        await tester.pumpWidget(const SizedBox());
        activity.dispose();
      },
    );
  }

  testWidgets('accepted message target opens the normal composer', (
    tester,
  ) async {
    targets.dispose();
    final chats = RequestsRepo()..isAccepted = true;
    targets = NotificationTargetsRepository(chats: chats);
    final repo = ReadingRepo()
      ..items = [
        notice('message_received', data: {'conversation_id': 42}),
      ];
    final activity = NotificationActivity(repo: repo);
    await tester.pumpWidget(
      app(
        NotificationsScreen(
          repo: repo,
          activity: activity,
          targets: targets,
          openDestination: (context, item, content) =>
              openNotificationDestination(context, item, content, chats: chats),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notification-n1')));
    await tester.pumpAndSettle();
    expect(find.byType(ChatComposer), findsOneWidget);
    expect(find.byType(ChatPendingRequestControls), findsNothing);
    await tester.pumpWidget(const SizedBox());
    activity.dispose();
  });

  testWidgets('opened content is hidden after account switching', (
    tester,
  ) async {
    final repo = ReadingRepo()
      ..items = [notice('post_liked', morph: r'App\Models\Post', target: 10)];
    final activity = NotificationActivity(repo: repo);
    await tester.pumpWidget(
      app(
        NotificationsScreen(repo: repo, activity: activity, targets: targets),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notification-n1')));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationPostScreen), findsOneWidget);
    await preferences.saveToken('replacement-session');
    await tester.pumpAndSettle();
    expect(find.byType(NotificationPostScreen), findsNothing);
    expect(find.text('Sign in again to view this content.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    // Drain cancellation of the replacement account's offstage preview lookup.
    targets.dispose();
    await tester.pumpAndSettle();
    activity.dispose();
  });

  testWidgets(
    'rapid duplicate taps coalesce detail fetch/navigation; deleted target remains in inbox',
    (tester) async {
      final repo = ReadingRepo()
        ..items = [notice('post_liked', morph: r'App\Models\Post', target: 10)];
      final activity = NotificationActivity(repo: repo);
      int opens = 0;
      await tester.pumpWidget(
        app(
          NotificationsScreen(
            repo: repo,
            activity: activity,
            targets: targets,
            openDestination: (context, item, content) async {
              opens++;
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('Destination')),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('notification-n1'));
      await tester.tap(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(opens, 1);
      expect(find.text('Destination'), findsOneWidget);
      Navigator.of(tester.element(find.text('Destination'))).pop();
      await tester.pumpAndSettle();
      adapter.status = 404;
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(opens, 1);
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(
        find.textContaining('This content is unavailable'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      activity.dispose();
    },
  );

  for (final story in [false, true]) {
    testWidgets(
      '${story ? 'story' : 'post'} media uses required geometry; text-only/follow/message reserve no media slot',
      (tester) async {
        final item = InboxNotification.fromJson(
          notice(story ? 'story_liked' : 'post_liked'),
        );
        await tester.pumpWidget(
          app(
            Scaffold(
              body: NotificationRow(
                item: item,
                onRead: () {},
                thumbnail: NotificationThumbnail(
                  url: 'https://fixtures.invalid/actual.png',
                  kind: story
                      ? NotificationMediaKind.story
                      : NotificationMediaKind.post,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final preview = find.byKey(
          ValueKey(
            story ? 'notification-story-preview' : 'notification-post-preview',
          ),
        );
        expect(tester.getSize(preview), Size(56, story ? 76 : 56));
        await tester.pumpWidget(
          app(
            Scaffold(
              body: NotificationRow(item: item, onRead: () {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(Image), findsNothing);
      },
    );
  }
}
