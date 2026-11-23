import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/chats/data/chat_hidden_messages.dart';
import 'package:travibe/features/chats/data/chat_message_reports.dart';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/data/chat_repository.dart';
import 'package:travibe/features/chats/screens/conversation_screen.dart';
import 'package:travibe/features/home/data/report_reason.dart';
import 'message_requests_test.dart';

const me = '1';
final sentAt = DateTime(DateTime.now().year, 4, 21, 2, 30);

class MenuRepo extends RequestsRepo {
  MenuRepo() {
    isAccepted = true;
    messageItems = [
      ChatMessage(
        id: '201',
        senderId: '7',
        kind: ChatMessageKind.text,
        text: 'Hello from them',
        createdAt: sentAt,
      ),
      ChatMessage(
        id: '202',
        senderId: me,
        kind: ChatMessageKind.text,
        text: 'My own note',
        createdAt: sentAt,
      ),
      ChatMessage(
        id: '203',
        senderId: '7',
        kind: ChatMessageKind.audio,
        duration: const Duration(seconds: 12),
        createdAt: sentAt,
      ),
    ];
  }
  final deletedIds = <String>[];
  @override
  Future<void> deleteMessage(String messageId) async {
    deletedIds.add(messageId);
    messageItems = [
      for (final m in messageItems) m.id == messageId ? m.asDeleted() : m,
    ];
  }
}

class ReportApi extends ApiService {
  final calls = <(String, Map<String, dynamic>)>[];
  Object? error;
  @override
  Future<dynamic> post(String endpoint, Map<String, dynamic> data) async {
    calls.add((endpoint, data));
    if (error != null) throw error!;
    return {
      'data': {'id': 1, 'status': 'pending'},
    };
  }
}

/// Records clipboard writes and haptic types on the platform channel.
({List<String> copied, List<String> haptics}) mockPlatform() {
  final copied = <String>[], haptics = <String>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      copied.add((call.arguments as Map)['text'] as String);
    } else if (call.method == 'HapticFeedback.vibrate') {
      haptics.add(call.arguments as String);
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return (copied: copied, haptics: haptics);
}

Future<void> openChat(
  WidgetTester tester,
  ChatRepository repo, {
  ChatHiddenMessages? hidden,
  ChatMessageReports? reports,
}) async {
  await tester.pumpWidget(
    requestApp(
      ConversationScreen(
        conversation: accepted,
        repository: repo,
        currentUserId: me,
        hiddenMessages: hidden ?? ChatHiddenMessages(),
        messageReports: reports ?? ChatMessageReports(apiService: ReportApi()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder option(String name) => find.byKey(ValueKey('chat-message-option-$name'));

Future<void> longPress(WidgetTester tester, Finder target) async {
  await tester.longPress(target);
  await tester.pumpAndSettle();
}

void main() {
  final preferences = PreferencesManager();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.saveToken('menu-fixture');
  });
  tearDown(() async => preferences.clear());

  group('sheet rows', () {
    testWidgets('their text: Copy, Delete for me, Report; no date header', (
      tester,
    ) async {
      final platform = mockPlatform();
      await openChat(tester, MenuRepo());
      await longPress(tester, find.text('Hello from them'));
      expect(find.text('Apr 21 at 2:30 AM'), findsNothing);
      expect(find.byType(Divider), findsNothing);
      expect(
        find.descendant(
          of: option('copy'),
          matching: find.byWidgetPredicate(
            (w) =>
                w is SvgPicture &&
                w.bytesLoader is SvgAssetLoader &&
                (w.bytesLoader as SvgAssetLoader).assetName ==
                    'assets/images/icons/copy.svg',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Copy message'), findsOneWidget);
      expect(find.text('Delete for me'), findsOneWidget);
      expect(find.text('Report'), findsOneWidget);
      expect(option('deleteForEveryone'), findsNothing);
      expect(find.text('Reply'), findsNothing);
      expect(find.text('Save'), findsNothing);
      expect(platform.haptics, ['HapticFeedbackType.mediumImpact']);
    });

    testWidgets('my text: Copy, Delete for me, Delete for everyone', (
      tester,
    ) async {
      mockPlatform();
      await openChat(tester, MenuRepo());
      await longPress(tester, find.text('My own note'));
      expect(option('copy'), findsOneWidget);
      expect(option('deleteForMe'), findsOneWidget);
      expect(find.text('Delete for everyone'), findsOneWidget);
      expect(option('report'), findsNothing);
    });

    testWidgets('non-text messages have no Copy row', (tester) async {
      mockPlatform();
      await openChat(tester, MenuRepo());
      await longPress(tester, find.text('0:12').first);
      expect(option('copy'), findsNothing);
      expect(option('deleteForMe'), findsOneWidget);
      expect(option('report'), findsOneWidget);
    });

    testWidgets('a bubble tap still toggles details', (tester) async {
      mockPlatform();
      await openChat(tester, MenuRepo());
      await tester.tap(find.text('Hello from them'));
      await tester.pumpAndSettle();
      expect(find.text('2:30 AM'), findsOneWidget);
      expect(option('copy'), findsNothing);
    });
  });

  testWidgets('Copy message copies the text and says Copied', (tester) async {
    final platform = mockPlatform();
    await openChat(tester, MenuRepo());
    await longPress(tester, find.text('Hello from them'));
    await tester.tap(option('copy'));
    await tester.pumpAndSettle();
    expect(platform.copied, ['Hello from them']);
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('Delete for me hides it for this account only and persists', (
    tester,
  ) async {
    mockPlatform();
    final repo = MenuRepo();
    await openChat(tester, repo);
    await longPress(tester, find.text('Hello from them'));
    await tester.tap(option('deleteForMe'));
    await tester.pumpAndSettle();
    expect(find.text('Hello from them'), findsNothing);
    expect(find.text('My own note'), findsOneWidget);
    expect(repo.deletedIds, isEmpty);
    expect(
      preferences.getString(
        '${PreferencesManager.chatHiddenMessagesPrefix}$me',
      ),
      '["201"]',
    );

    // A fresh store reads it back; logout keeps it for the same account.
    await preferences.clearSession();
    await preferences.saveToken('menu-fixture-2');
    await tester.pumpWidget(const SizedBox());
    await openChat(tester, MenuRepo());
    expect(find.text('Hello from them'), findsNothing);
    expect(find.text('My own note'), findsOneWidget);
    expect(ChatHiddenMessages().ids('2'), isEmpty);
  });

  group('Delete for everyone', () {
    testWidgets('Cancel keeps the message', (tester) async {
      mockPlatform();
      final repo = MenuRepo();
      await openChat(tester, repo);
      await longPress(tester, find.text('My own note'));
      await tester.tap(option('deleteForEveryone'));
      await tester.pumpAndSettle();
      expect(find.text('Delete for everyone?'), findsOneWidget);
      expect(
        find.text('This message will be removed for both of you.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.deletedIds, isEmpty);
      expect(find.text('My own note'), findsOneWidget);
    });

    testWidgets('confirming deletes it for both', (tester) async {
      mockPlatform();
      final repo = MenuRepo();
      await openChat(tester, repo);
      await longPress(tester, find.text('My own note'));
      await tester.tap(option('deleteForEveryone'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(repo.deletedIds, ['202']);
      expect(find.text('My own note'), findsNothing);
      expect(find.text('Message deleted'), findsOneWidget);
    });
  });

  group('Report', () {
    Future<ReportApi> report(WidgetTester tester, {Object? error}) async {
      mockPlatform();
      final api = ReportApi()..error = error;
      await openChat(
        tester,
        MenuRepo(),
        reports: ChatMessageReports(apiService: api),
      );
      await longPress(tester, find.text('Hello from them'));
      await tester.tap(option('report'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('report-reason-harassment')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('report-submit')));
      await tester.pumpAndSettle();
      return api;
    }

    testWidgets('sends type=message and thanks the user', (tester) async {
      final api = await report(tester);
      expect(api.calls.single.$1, 'reports');
      expect(api.calls.single.$2, {
        'type': 'message',
        'id': 201,
        'reason': 'harassment',
      });
      expect(find.text("Thanks, we'll review this message"), findsOneWidget);
    });

    testWidgets('an already-pending report says so', (tester) async {
      await report(
        tester,
        error: ApiError(
          statusCode: 422,
          message: 'You have already reported this message.',
        ),
      );
      expect(
        find.text("You've already reported this message. We're reviewing it."),
        findsOneWidget,
      );
    });

    testWidgets('a gone message says it is unavailable', (tester) async {
      await report(
        tester,
        error: ApiError(statusCode: 404, message: 'Not found'),
      );
      expect(find.text('This message is no longer available.'), findsOneWidget);
    });

    testWidgets('other failures explain and offer Retry', (tester) async {
      final api = await report(
        tester,
        error: ApiError(statusCode: 500, message: 'Server unavailable'),
      );
      expect(find.text('Server unavailable'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      api.error = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(api.calls, hasLength(2));
      expect(find.text("Thanks, we'll review this message"), findsOneWidget);
    });
  });

  group('ChatMessageReports', () {
    test('trims and caps the description', () async {
      final api = ReportApi();
      await ChatMessageReports(apiService: api).reportMessage(
        '9',
        ReportReason.somethingElse,
        description: '  ${'x' * 1200}  ',
      );
      final body = api.calls.single.$2;
      expect(body['type'], 'message');
      expect((body['description'] as String).length, 1000);
    });

    test('rejects non-numeric ids without a request', () async {
      final api = ReportApi();
      await expectLater(
        ChatMessageReports(
          apiService: api,
        ).reportMessage('local-1', ReportReason.spamOrScam),
        throwsArgumentError,
      );
      expect(api.calls, isEmpty);
    });
  });
}
