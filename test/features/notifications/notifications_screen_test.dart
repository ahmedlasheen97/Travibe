import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/cursor_pagination.dart';
import 'package:travibe/core/notifications/push_message.dart';
import 'package:travibe/core/notifications/push_notification_service.dart';
import 'package:travibe/core/notifications/push_notifications_host.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/notifications/data/notifications_repo.dart';
import 'package:travibe/features/notifications/screens/notifications_screen.dart';
import '../../core/notifications/push_fakes.dart';
import 'package:travibe/features/notifications/data/notification_model.dart';

class InboxRepo extends NotificationsRepo {
  @override
  Future<NotificationUnreadCount> unreadCount() async =>
      NotificationUnreadCount(items.where((n) => n['read_at'] == null).length);
  @override
  Future<void> markRead(String id) async {
    items = [
      for (final n in items)
        if (n['id'].toString() == id)
          {...n, 'read_at': DateTime.now().toIso8601String()}
        else
          n,
    ];
  }

  @override
  Future<void> markAllRead() async {
    items = [
      for (final n in items)
        {...n, 'read_at': DateTime.now().toIso8601String()},
    ];
  }

  final requests = <String?>[];
  Completer<CursorPage<Map<String, dynamic>>>? gate;
  bool fail = false;
  List<Map<String, dynamic>> items = [];
  @override
  Future<CursorPage<Map<String, dynamic>>> list({
    String? cursor,
    int perPage = 15,
  }) async {
    requests.add(cursor);
    if (gate != null) return gate!.future;
    if (fail) throw ApiError(message: 'Please retry notifications');
    return page(items);
  }
}

CursorPage<Map<String, dynamic>> page(List<Map<String, dynamic>> items) =>
    CursorPage(
      items: items,
      pagination: const CursorPaginationMeta(
        path: 'notifications',
        perPage: 15,
      ),
    );
Widget app(Widget home) => ScreenUtilInit(
  designSize: const Size(390, 844),
  builder: (_, _) => MaterialApp(theme: darkTheme, home: home),
);

void main() {
  final prefs = PreferencesManager();
  late InboxRepo repo;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'_token': 'auth'});
    await prefs.init();
    repo = InboxRepo();
  });
  tearDown(() => prefs.clear());
  testWidgets(
    'loading then empty and error/retry states use Laravel repository',
    (tester) async {
      repo.gate = Completer();
      await tester.pumpWidget(app(NotificationsScreen(repo: repo)));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      repo.gate!.complete(page([]));
      await tester.pumpAndSettle();
      expect(find.text('No notifications yet.'), findsOneWidget);
      repo.gate = null;
      repo.fail = true;
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(find.text('Please retry notifications'), findsOneWidget);
      repo.fail = false;
      repo.items = [
        {
          'id': 'n1',
          'data': {'title': 'From Laravel', 'body': 'Server content'},
        },
      ];
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('New notification', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Server content', findRichText: true),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'logout clears cached inbox; late old request cannot restore it',
    (tester) async {
      repo.gate = Completer();
      await tester.pumpWidget(app(NotificationsScreen(repo: repo)));
      await prefs.clearSession();
      await tester.pump();
      repo.gate!.complete(
        page([
          {'id': 1, 'title': 'Old account'},
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Old account'), findsNothing);
      expect(find.text('Sign in to view your notifications.'), findsOneWidget);
      expect(repo.requests, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'bell and duplicate push taps open one read-only inbox; detach disables navigation',
    (tester) async {
      final client = FakeMessagingClient();
      final service = PushNotificationService(client: client);
      final coordinator = PushNotificationsCoordinator(
        service,
        repository: repo,
      );
      final owner = Object();
      late BuildContext rootContext;
      await service.updateAccount('1', expectedSession: prefs.sessionRevision);
      await service.start();
      await drainPush();
      await tester.pumpWidget(
        app(
          PushNotificationsScope(
            coordinator: coordinator,
            child: Builder(
              builder: (context) {
                rootContext = context;
                return Scaffold(
                  body: IconButton(
                    tooltip: 'Notifications',
                    icon: const Icon(Icons.notifications),
                    onPressed: () => PushNotificationsScope.openInbox(context),
                  ),
                );
              },
            ),
          ),
        ),
      );
      coordinator.attach(owner, rootContext);
      coordinator.attach(owner, rootContext);
      await tester.tap(find.byTooltip('Notifications'));
      client.taps.add(
        PushMessage(
          id: 'tap',
          data: {'route': 'https://unsafe', 'post_id': 99},
        ),
      );
      client.taps.add(PushMessage(id: 'tap'));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(repo.requests, hasLength(1));
      Navigator.of(rootContext).pop();
      await tester.pumpAndSettle();
      coordinator.detach(owner);
      client.taps.add(PushMessage(id: 'second'));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationsScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
      coordinator.dispose();
      service.dispose();
      await client.close();
    },
  );
  for (final width in [320.0, 375.0, 393.0, 430.0]) {
    testWidgets('read-only inbox fits $width with larger text', (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      repo.items = [
        {
          'id': 1,
          'data': {
            'title': 'Notification with a long title',
            'body':
                'Authoritative Laravel data with line breaks\nand emojis 🌴',
          },
        },
      ];
      await tester.pumpWidget(
        app(
          MediaQuery(
            data: MediaQueryData(
              size: Size(width, 844),
              textScaler: TextScaler.linear(1.8),
            ),
            child: NotificationsScreen(repo: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('New notification', findRichText: true),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });
  }
}
