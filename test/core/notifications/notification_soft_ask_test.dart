import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/notifications/firebase_messaging_client.dart';
import 'package:travibe/core/notifications/notification_soft_ask.dart';
import 'package:travibe/core/notifications/push_notification_service.dart';

import 'push_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final prefs = PreferencesManager();
  var now = DateTime.utc(2026, 11, 18, 12);
  NotificationPromptPolicy policy() =>
      NotificationPromptPolicy(clock: () => now);

  setUp(() async {
    SharedPreferences.setMockInitialValues({'_token': 'auth-a'});
    await prefs.init();
    now = DateTime.utc(2026, 11, 18, 12);
  });
  tearDown(() => prefs.clear());

  group('NotificationPromptPolicy', () {
    bool ask(
      NotificationPromptTrigger trigger, {
      bool supported = true,
      PushPermission permission = PushPermission.notDetermined,
    }) => policy().shouldAsk(
      trigger,
      supported: supported,
      permission: permission,
    );

    test('asks only while the system has never asked', () {
      for (final permission in PushPermission.values) {
        expect(
          ask(NotificationPromptTrigger.afterSetup, permission: permission),
          permission == PushPermission.notDetermined,
          reason: '$permission',
        );
      }
      expect(
        ask(NotificationPromptTrigger.afterSetup, supported: false),
        isFalse,
      );
    });

    test('each trigger asks once, at most every 3 days', () async {
      await policy().recordShown(NotificationPromptTrigger.afterSetup);
      expect(ask(NotificationPromptTrigger.afterSetup), isFalse);
      // Another relevant moment inside the cooldown waits.
      now = now.add(const Duration(days: 2, hours: 23));
      expect(ask(NotificationPromptTrigger.firstFollow), isFalse);
      expect(ask(NotificationPromptTrigger.firstChatMessage), isFalse);
      now = now.add(const Duration(hours: 1));
      expect(ask(NotificationPromptTrigger.firstFollow), isTrue);
      await policy().recordShown(NotificationPromptTrigger.firstFollow);
      expect(ask(NotificationPromptTrigger.firstChatMessage), isFalse);
      now = now.add(const Duration(days: 3));
      expect(ask(NotificationPromptTrigger.firstChatMessage), isTrue);
      // Used triggers never come back, however long ago.
      expect(ask(NotificationPromptTrigger.afterSetup), isFalse);
      expect(ask(NotificationPromptTrigger.firstFollow), isFalse);
    });

    test('history survives logout; the permission is device-wide', () async {
      await policy().recordShown(NotificationPromptTrigger.afterSetup);
      await prefs.clearSession();
      expect(ask(NotificationPromptTrigger.afterSetup), isFalse);
      expect(ask(NotificationPromptTrigger.firstFollow), isFalse);
    });
  });

  group('NotificationSoftAsk', () {
    late FakeMessagingClient client;
    late PushNotificationService push;

    setUp(() {
      client = FakeMessagingClient()..status = PushPermission.notDetermined;
      push = PushNotificationService(
        client: client,
        repository: FakePushRepository(),
      );
    });
    tearDown(() async {
      push.dispose();
      await client.close();
    });

    Future<BuildContext> pump(WidgetTester tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            home: Builder(
              builder: (c) {
                context = c;
                return const Scaffold();
              },
            ),
          ),
        ),
      );
      return context;
    }

    Future<bool> show(
      WidgetTester tester,
      BuildContext context, [
      NotificationPromptTrigger trigger = NotificationPromptTrigger.afterSetup,
    ]) async {
      final shown = NotificationSoftAsk.maybeShow(
        context,
        trigger,
        push: push,
        policy: policy(),
      );
      await tester.pumpAndSettle();
      return shown;
    }

    testWidgets('Turn On shows the system prompt', (tester) async {
      final context = await pump(tester);
      final shown = NotificationSoftAsk.maybeShow(
        context,
        NotificationPromptTrigger.afterSetup,
        push: push,
        policy: policy(),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('notification-soft-ask')), findsOne);
      expect(find.text('Turn on notifications'), findsOneWidget);
      expect(
        find.text(
          'Get notified when someone follows you, likes your posts or '
          'sends you a message',
        ),
        findsOneWidget,
      );
      expect(find.text('Not Now'), findsOneWidget);
      expect(client.prompts, 0);
      client.status = PushPermission.authorized;
      await tester.tap(find.text('Turn On'));
      await tester.pumpAndSettle();
      expect(await shown, isTrue);
      expect(client.prompts, 1);
      expect(push.permission, PushPermission.authorized);
    });

    testWidgets('Not Now never shows the system prompt', (tester) async {
      final context = await pump(tester);
      final shown = NotificationSoftAsk.maybeShow(
        context,
        NotificationPromptTrigger.firstFollow,
        push: push,
        policy: policy(),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not Now'));
      await tester.pumpAndSettle();
      expect(await shown, isTrue);
      expect(client.prompts, 0);
      expect(find.text('Turn on notifications'), findsNothing);
      // Same trigger again: no nagging.
      final again = NotificationSoftAsk.maybeShow(
        context,
        NotificationPromptTrigger.firstFollow,
        push: push,
        policy: policy(),
      );
      await tester.pumpAndSettle();
      expect(await again, isFalse);
      expect(find.text('Turn on notifications'), findsNothing);
    });

    for (final status in [
      PushPermission.authorized,
      PushPermission.provisional,
      PushPermission.denied,
    ]) {
      testWidgets('nothing is shown when permission is $status', (
        tester,
      ) async {
        client.status = status;
        final context = await pump(tester);
        expect(await show(tester, context), isFalse);
        expect(find.text('Turn on notifications'), findsNothing);
        expect(client.prompts, 0);
      });
    }

    testWidgets('a sheet torn down unanswered does not block later asks', (
      tester,
    ) async {
      var context = await pump(tester);
      // Left open while the app shell is replaced (e.g. logout).
      unawaited(
        NotificationSoftAsk.maybeShow(
          context,
          NotificationPromptTrigger.afterSetup,
          push: push,
          policy: policy(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Turn on notifications'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      now = now.add(const Duration(days: 4));
      context = await pump(tester);
      final shown = NotificationSoftAsk.maybeShow(
        context,
        NotificationPromptTrigger.firstFollow,
        push: push,
        policy: policy(),
      );
      await tester.pumpAndSettle();
      expect(find.text('Turn on notifications'), findsOneWidget);
      await tester.tap(find.text('Not Now'));
      await tester.pumpAndSettle();
      expect(await shown, isTrue);
    });

    testWidgets('nothing is shown when push is unavailable', (tester) async {
      client.available = false;
      final context = await pump(tester);
      expect(await show(tester, context), isFalse);
      expect(find.text('Turn on notifications'), findsNothing);
    });

    testWidgets('without a push service in scope nothing happens', (
      tester,
    ) async {
      final context = await pump(tester);
      expect(
        await NotificationSoftAsk.maybeShow(
          context,
          NotificationPromptTrigger.firstChatMessage,
          policy: policy(),
        ),
        isFalse,
      );
    });
  });
}
