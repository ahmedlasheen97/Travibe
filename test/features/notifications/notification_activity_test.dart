import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/core/models/cursor_pagination.dart';
import 'package:travibe/features/notifications/cubit/notification_activity.dart';
import 'package:travibe/features/notifications/cubit/notifications_cubit.dart';
import 'package:travibe/features/notifications/data/notification_model.dart';
import 'package:travibe/features/notifications/data/notifications_repo.dart';
import 'package:travibe/features/home/widgets/home_top_bar.dart';
import 'package:travibe/core/notifications/push_notifications_host.dart';
import 'package:travibe/core/notifications/push_notification_service.dart';
import 'package:travibe/core/notifications/push_message.dart';
import '../../core/notifications/push_fakes.dart';

class ActivityRepo extends NotificationsRepo {
  int value = 2, counts = 0, writes = 0;
  bool fail = false;
  Completer<NotificationUnreadCount>? countGate;
  Completer<void>? writeGate;
  @override
  Future<NotificationUnreadCount> unreadCount() async {
    counts++;
    return countGate == null
        ? NotificationUnreadCount(value)
        : countGate!.future;
  }

  @override
  Future<void> markRead(String id) async {
    writes++;
    if (writeGate != null) await writeGate!.future;
    if (fail) throw ApiError(message: 'Retry read');
    value--;
  }

  @override
  Future<void> markAllRead() async {
    writes++;
    if (writeGate != null) await writeGate!.future;
    if (fail) throw ApiError(message: 'Retry read');
    value = 0;
  }

  @override
  Future<CursorPage<Map<String, dynamic>>> list({
    String? cursor,
    int perPage = 15,
  }) async => CursorPage(
    items: [
      {'id': 'one', 'type': 'follow', 'read_at': null},
      {'id': 'two', 'type': 'like', 'read_at': null},
    ],
    pagination: const CursorPaginationMeta(
      path: 'notifications',
      perPage: 15,
      nextCursor: 'opaque',
    ),
  );
}

class CursorApi extends ApiService {
  final cursors = <String?>[];
  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
    cursors.add(queryParameters?['cursor']);
    return {
      'data': [
        {
          'id': cursors.length == 1 ? 'one' : 'two',
          'type': 'follow',
          'actor': {'id': 7, 'name': 'Mona'},
          'read_at': null,
        },
      ],
      'links': {'next': null},
      'meta': {
        'per_page': 15,
        'next_cursor': cursors.length == 1 ? 'opaque+cursor==' : null,
        'prev_cursor': null,
      },
    };
  }
}

void main() {
  final prefs = PreferencesManager();
  late ActivityRepo repo;
  late NotificationActivity activity;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'_token': 'a'});
    await prefs.init();
    repo = ActivityRepo();
    activity = NotificationActivity(repo: repo);
  });
  tearDown(() async {
    activity.dispose();
    await prefs.clear();
  });
  for (final count in [0, 1, 99, 100, 125]) {
    test(
      'parses exact unread count $count',
      () => expect(
        NotificationUnreadCount.fromJson({
          'data': {'unread_count': count},
        }).value,
        count,
      ),
    );
    testWidgets('badge for $count hides zero and caps at 99+', (tester) async {
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            home: Scaffold(
              body: HomeTopBar(
                unreadCount: count,
                onMessagesTap: () {},
                onNotificationsTap: () {},
              ),
            ),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('notification-unread-badge')),
        count == 0 ? findsNothing : findsOneWidget,
      );
      if (count > 0) {
        expect(find.text(count > 99 ? '99+' : '$count'), findsOneWidget);
      }
    });
  }
  test('invalid unread count fails without guessing zero', () {
    for (final value in [-1, '3', null, 1.5]) {
      expect(
        () => NotificationUnreadCount.fromJson({
          'data': {'unread_count': value},
        }),
        throwsA(isA<ApiError>()),
      );
    }
  });
  test(
    'confirmed no-path cursor response uses opaque next_cursor, not links',
    () async {
      final api = CursorApi();
      final cubit = NotificationsCubit(
        repo: NotificationsRepo(apiService: api),
      );
      await cubit.load();
      await cubit.more();
      expect(api.cursors, [null, 'opaque+cursor==']);
      expect(cubit.state.items.map((n) => n['id']), ['one', 'two']);
      await cubit.close();
    },
  );
  test(
    'read-one/read-all synchronize loaded cursor cache and authoritative count',
    () async {
      final cubit = NotificationsCubit(activity: activity);
      await cubit.load();
      await activity.refresh();
      expect(activity.count, 2);
      expect(await activity.markRead('one'), true);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.items.first['read_at'], isNotNull);
      expect(cubit.state.items.last['read_at'], isNull);
      expect(activity.count, 1);
      expect(await activity.markAllRead(ids: ['one', 'two']), true);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.items.every((n) => n['read_at'] != null), true);
      expect(activity.count, 0);
      expect(cubit.nextCursor, 'opaque');
      await cubit.close();
    },
  );
  test('failed write does not mark rows read or change count', () async {
    final cubit = NotificationsCubit(activity: activity);
    await cubit.load();
    await activity.refresh();
    repo.fail = true;
    expect(await activity.markRead('one'), false);
    expect(activity.count, 2);
    expect(cubit.state.items.first['read_at'], isNull);
    await cubit.close();
  });
  test('duplicate read operations coalesce', () async {
    repo.writeGate = Completer<void>();
    final a = activity.markRead('one'), b = activity.markRead('one');
    expect(repo.writes, 1);
    repo.writeGate!.complete();
    expect(await a, true);
    expect(await b, true);
  });
  test('late count after account switch cannot restore old badge', () async {
    repo.countGate = Completer();
    final pending = activity.refresh();
    await prefs.saveToken('b');
    expect(activity.count, 0);
    repo.countGate!.complete(const NotificationUnreadCount(99));
    await pending;
    expect(activity.count, 0);
    repo.countGate = null;
    repo.value = 4;
    await activity.refresh();
    expect(activity.count, 4);
  });
  test(
    'count in flight during read is invalidated and fetched again',
    () async {
      repo.countGate = Completer();
      final oldGate = repo.countGate!;
      final first = activity.refresh();
      final read = activity.markRead('one');
      await Future<void>.value();
      await Future<void>.value();
      repo.countGate = null;
      oldGate.complete(const NotificationUnreadCount(50));
      await first;
      await read;
      expect(activity.count, 1);
      expect(repo.counts, 2);
    },
  );
  test(
    'late successful read does not affect next account or its badge',
    () async {
      repo.writeGate = Completer();
      final read = activity.markRead('one');
      await prefs.saveToken('b');
      repo.writeGate!.complete();
      expect(await read, false);
      expect(activity.count, 0);
      expect(repo.counts, 0);
    },
  );
  testWidgets('shared badge refreshes on FCM activity and returning to Home', (
    tester,
  ) async {
    repo.value = 0;
    final client = FakeMessagingClient();
    final push = PushNotificationService(client: client);
    final coordinator = PushNotificationsCoordinator(push, repository: repo);
    final owner = Object();
    late BuildContext routeContext;
    await push.updateAccount('7', expectedSession: prefs.sessionRevision);
    await push.start();
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => PushNotificationsScope(
          coordinator: coordinator,
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                routeContext = context;
                return Scaffold(
                  body: HomeTopBar(
                    onMessagesTap: () {},
                    onNotificationsTap: () =>
                        PushNotificationsScope.openInbox(context),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    final mountedContext = routeContext;
    if (!mountedContext.mounted) throw StateError('Detached test route');
    coordinator.attach(owner, mountedContext);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('notification-unread-badge')),
      findsNothing,
    );
    repo.value = 120;
    client.messages.add(PushMessage(id: 'activity'));
    await tester.pumpAndSettle();
    expect(find.text('99+'), findsOneWidget);
    final navigator = Navigator.of(mountedContext);
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Other route')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    repo.value = 3;
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);
    // Opening the inbox clears the bell before read-all even returns.
    repo.writeGate = Completer<void>();
    final writes = repo.writes;
    await tester.tap(find.byKey(const ValueKey('home-notification-bell')));
    await tester.pump();
    await tester.pump();
    expect(coordinator.notifications.count, 0);
    expect(find.byTooltip('Notification options'), findsNothing);
    expect(find.byIcon(Icons.more_horiz), findsNothing);
    expect(find.byIcon(Icons.more_vert), findsNothing);
    repo.writeGate!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(repo.writes, writes + 1);
    expect(coordinator.notifications.count, 0);
    // Rows unread on entry keep their dot for this visit.
    expect(
      find.byKey(const ValueKey('notification-unread-one')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('notification-unread-two')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await prefs.clearSession();
    await tester.pumpAndSettle();
    expect(find.text('Sign in to view your notifications.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    coordinator.dispose();
    push.dispose();
    await client.close();
  });
  test('typed actor, dates, description and read state come from Laravel', () {
    final item = InboxNotification.fromJson({
      'id': 'uuid',
      'type': r'App\Notifications\Follow',
      'actor': {'name': 'Mona', 'avatar_url': null},
      'data': {'body': 'Followed you'},
      'read_at': null,
      'created_at': '2026-11-06T10:00:00Z',
    });
    expect(item.actor!.name, 'Mona');
    expect(item.isRead, false);
    expect(item.description, 'Followed you');
    expect(item.createdAt, isNotNull);
  });
}
