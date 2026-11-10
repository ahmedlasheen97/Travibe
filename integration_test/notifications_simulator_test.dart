import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/main.dart' as app;
import 'package:travibe/root.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/models/cursor_pagination.dart';
import 'package:travibe/core/notifications/firebase_messaging_client.dart';
import 'package:travibe/core/notifications/push_message.dart';
import 'package:travibe/core/notifications/push_notification_service.dart';
import 'package:travibe/core/notifications/push_notifications_host.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/auth/screens/login_screen.dart';
import 'package:travibe/features/onboarding/screens/onboarding_screen.dart';
import 'package:travibe/features/onboarding/screens/splash_screen.dart';
import 'package:travibe/features/home/widgets/home_top_bar.dart';
import 'package:travibe/features/notifications/data/notification_model.dart';
import 'package:travibe/features/notifications/data/notifications_repo.dart';
import 'package:travibe/features/notifications/screens/notifications_screen.dart';
import 'support/test_reporting.dart';

/// Unsupported-capability adapter lives only in this test entry point.
class UnavailableSimulatorMessaging implements MessagingClient {
  @override
  String get platform => 'iOS';
  @override
  bool get requiresApns => true;
  @override
  Future<bool> initialize() async => false;
  @override
  Future<PushPermission> permission() async => PushPermission.denied;
  @override
  Future<PushPermission> requestPermission() async => PushPermission.denied;
  @override
  Future<String?> apnsToken() async => null;
  @override
  Future<String?> token() async => null;
  @override
  Future<void> deleteToken() async {}
  @override
  Future<PushMessage?> initialMessage() async => null;
  @override
  Stream<String> get tokenRefresh => const Stream.empty();
  @override
  Stream<PushMessage> get foreground => const Stream.empty();
  @override
  Stream<PushMessage> get opened => const Stream.empty();
}

class SimulatorInboxFixture extends NotificationsRepo {
  final items = <Map<String, dynamic>>[
    {
      'id': 'sim-one',
      'type': 'user_followed',
      'actor': {'id': 7, 'name': 'Fixture traveler'},
      'data': {'body': 'Simulator-only test notification'},
      'read_at': null,
      'created_at': '2026-11-06T10:00:00Z',
    },
    {
      'id': 'sim-two',
      'type': 'post_liked',
      'actor': {'id': 8, 'name': 'Another fixture traveler'},
      'data': {},
      'read_at': null,
    },
  ];
  @override
  Future<NotificationUnreadCount> unreadCount() async =>
      NotificationUnreadCount(items.where((n) => n['read_at'] == null).length);
  @override
  Future<CursorPage<Map<String, dynamic>>> list({
    String? cursor,
    int perPage = 15,
  }) async => CursorPage(
    items: items.map((n) => Map<String, dynamic>.of(n)),
    pagination: const CursorPaginationMeta(path: 'notifications', perPage: 15),
  );
  @override
  Future<void> markRead(String id) async {
    items.firstWhere((n) => n['id'] == id)['read_at'] = DateTime.now()
        .toIso8601String();
  }

  @override
  Future<void> markAllRead() async {
    for (final n in items) {
      n['read_at'] = DateTime.now().toIso8601String();
    }
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerTestReporting(binding);
  testWidgets(
    'real persisted startup is usable without requesting notification permission',
    (tester) async {
      // Reads existing simulator preferences. No clearing, mock session or disk write.
      await PreferencesManager().init();
      await tester.pumpWidget(const app.MyApp());
      await tester.pump();
      for (
        var i = 0;
        i < 120 && find.byType(SplashScreen).evaluate().isNotEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 250)),
        );
        await tester.pump(const Duration(milliseconds: 250));
      }
      final home = find.byType(Root).evaluate().isNotEmpty;
      final login = find.byType(LoginScreen).evaluate().isNotEmpty;
      final onboarding = find.byType(OnboardingScreen).evaluate().isNotEmpty;
      // Only a route name is reported; credentials and user content are not logged.
      debugPrint(
        'SIMULATOR_REAL_STARTUP: ${home
            ? 'Home'
            : login
            ? 'Login'
            : onboarding
            ? 'Onboarding'
            : 'Other guarded route'}',
      );
      expect(find.byType(SplashScreen), findsNothing);
      expect(tester.takeException(), isNull);
      if (home) {
        await tester.tap(find.byKey(const ValueKey('home-notification-bell')));
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 20),
        );
        expect(find.byType(NotificationsScreen), findsOneWidget);
        debugPrint(
          'SIMULATOR_REAL_INBOX: opened with restored session; no read/logout mutation performed',
        );
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets(
    'mock inbox count and read actions work when messaging is unavailable',
    (tester) async {
      // In-process preferences override only; no real user session is overwritten.
      SharedPreferences.setMockInitialValues({'_token': 'simulator-test-only'});
      final prefs = PreferencesManager();
      await prefs.init();
      final repo = SimulatorInboxFixture();
      final push = PushNotificationService(
        client: UnavailableSimulatorMessaging(),
      );
      final coordinator = PushNotificationsCoordinator(push, repository: repo);
      final owner = Object();
      late BuildContext homeContext;
      await push.start();
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => PushNotificationsScope(
            coordinator: coordinator,
            child: MaterialApp(
              theme: darkTheme,
              home: Builder(
                builder: (context) {
                  homeContext = context;
                  return Scaffold(
                    body: SafeArea(
                      child: HomeTopBar(
                        name: 'Simulator test',
                        onMessagesTap: () {},
                        onNotificationsTap: () =>
                            PushNotificationsScope.openInbox(context),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      final mountedContext = homeContext;
      if (!mountedContext.mounted) {
        throw StateError('Simulator test context detached');
      }
      coordinator.attach(owner, mountedContext);
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home-notification-bell')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Fixture traveler', findRichText: true),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Notification options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notification settings'));
      await tester.pumpAndSettle();
      expect(
        find.text('Push notifications are not configured on this device.'),
        findsOneWidget,
      );
      Navigator.of(
        tester.element(find.byType(NotificationPermissionCard)),
      ).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('notification-sim-one')));
      await tester.pumpAndSettle();
      expect(coordinator.notifications.count, 1);
      await tester.tap(find.byTooltip('Notification options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark all as read'));
      await tester.pumpAndSettle();
      expect(coordinator.notifications.count, 0);
      expect(
        find.byKey(const ValueKey('notification-unread-sim-one')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('notification-unread-sim-two')),
        findsNothing,
      );
      await prefs.clearSession();
      await tester.pumpAndSettle();
      expect(find.text('Sign in to view your notifications.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      coordinator.dispose();
      push.dispose();
    },
  );
}
