import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/chats/data/chat_hidden_messages.dart';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/data/chat_repository.dart';
import 'package:travibe/features/chats/screens/conversation_screen.dart';
import 'package:travibe/features/chats/widgets/chat_reply_preview.dart';
import 'chat_message_menu_test.dart' show MenuRepo, ReportApi, me, mockPlatform;
import 'package:travibe/features/chats/data/chat_message_reports.dart';
import 'message_requests_test.dart';

/// 300 is the original; 301–340 are fillers; 341 replies to [replyTo].
class LongRepo extends RequestsRepo {
  LongRepo({required Map<String, dynamic> replyTo, this.paged = false}) {
    isAccepted = true;
    final at = DateTime(2026, 4, 21, 2, 30);
    messageItems = [
      ChatMessage(
        id: '300',
        senderId: '7',
        kind: ChatMessageKind.text,
        text: 'The original question',
        createdAt: at,
      ),
      for (var i = 301; i <= 340; i++)
        ChatMessage(
          id: '$i',
          senderId: i.isEven ? me : '7',
          kind: ChatMessageKind.text,
          text: 'Filler $i',
          createdAt: at,
        ),
      ChatMessage(
        id: '341',
        senderId: me,
        kind: ChatMessageKind.text,
        text: 'My answer',
        createdAt: at,
        replyTo: ChatLastMessage.fromJson(replyTo),
      ),
    ];
  }
  final bool paged;
  final pages = <String?>[];
  @override
  Future<ChatPage<ChatMessage>> messages(
    String id, {
    String? continuation,
  }) async {
    pages.add(continuation);
    if (!paged) return ChatPage(messageItems);
    return continuation == null
        ? ChatPage(messageItems.skip(20), continuation: 'older')
        : ChatPage(messageItems.take(20));
  }
}

Future<void> openChat(
  WidgetTester tester,
  ChatRepository repo, {
  TextDirection direction = TextDirection.ltr,
}) async {
  await tester.pumpWidget(
    requestApp(
      Directionality(
        textDirection: direction,
        child: ConversationScreen(
          conversation: accepted,
          repository: repo,
          currentUserId: me,
          hiddenMessages: ChatHiddenMessages(),
          messageReports: ChatMessageReports(apiService: ReportApi()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final replyBar = find.byKey(const ValueKey('chat-reply-bar'));

Future<void> swipe(WidgetTester tester, Finder target, double dx) async {
  await tester.drag(target, Offset(dx, 0));
  await tester.pumpAndSettle();
}

bool composerFocused(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus;

void main() {
  final preferences = PreferencesManager();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.saveToken('reply-fixture');
  });
  tearDown(() async => preferences.clear());

  group('swipe to reply', () {
    testWidgets('a swipe right starts a reply, buzzes and opens the keyboard', (
      tester,
    ) async {
      final platform = mockPlatform();
      await openChat(tester, MenuRepo());
      expect(replyBar, findsNothing);
      await swipe(tester, find.text('Hello from them'), 120);
      expect(replyBar, findsOneWidget);
      expect(
        find.descendant(of: replyBar, matching: find.text('Hello from them')),
        findsOneWidget,
      );
      expect(find.text('Replying to Request Person'), findsOneWidget);
      expect(platform.haptics, ['HapticFeedbackType.lightImpact']);
      expect(composerFocused(tester), isTrue);
    });

    testWidgets('a short swipe or a swipe left does nothing', (tester) async {
      final platform = mockPlatform();
      await openChat(tester, MenuRepo());
      await swipe(tester, find.text('Hello from them'), 30);
      await swipe(tester, find.text('Hello from them'), -120);
      expect(replyBar, findsNothing);
      expect(platform.haptics, isEmpty);
    });

    testWidgets('RTL replies on a swipe left only', (tester) async {
      mockPlatform();
      await openChat(tester, MenuRepo(), direction: TextDirection.rtl);
      await swipe(tester, find.text('Hello from them'), 120);
      expect(replyBar, findsNothing);
      await swipe(tester, find.text('Hello from them'), -120);
      expect(replyBar, findsOneWidget);
    });

    testWidgets('vertical drags still scroll the history', (tester) async {
      mockPlatform();
      await openChat(
        tester,
        LongRepo(
          replyTo: {'id': 300, 'sender_id': 7, 'type': 'text', 'body': 'x'},
        ),
      );
      ScrollPosition history() => tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(ListView),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      expect(history().pixels, 0);
      await tester.drag(find.text('My answer'), const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(history().pixels, greaterThan(100));
      expect(replyBar, findsNothing);
    });
  });

  group('reply bar', () {
    testWidgets('my message says Replying to You; ✕ cancels', (tester) async {
      mockPlatform();
      await openChat(tester, MenuRepo());
      await swipe(tester, find.text('My own note'), 120);
      expect(find.text('Replying to You'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-reply-cancel')));
      await tester.pumpAndSettle();
      expect(replyBar, findsNothing);
    });

    testWidgets('a voice note previews its length', (tester) async {
      mockPlatform();
      await openChat(tester, MenuRepo());
      await swipe(tester, find.text('0:12').first, 120);
      expect(
        find.descendant(
          of: replyBar,
          matching: find.text('🎤 Voice note · 0:12'),
        ),
        findsOneWidget,
      );
    });

    test('one-line previews per message kind', () {
      expect(chatReplyText(kind: ChatMessageKind.image, body: ''), '📷 Photo');
      expect(chatReplyText(kind: ChatMessageKind.video, body: ''), '🎥 Video');
      expect(
        chatReplyText(
          kind: ChatMessageKind.audio,
          body: '',
          duration: const Duration(seconds: 72),
        ),
        '🎤 Voice note · 1:12',
      );
      expect(
        chatReplyText(kind: ChatMessageKind.post, body: ''),
        'Shared a post',
      );
      expect(
        chatReplyText(
          kind: ChatMessageKind.text,
          body: 'Nice\nview',
          storyReply: true,
        ),
        'Story reply · Nice view',
      );
    });

    test('snapshots preview photos with their thumbnail', () {
      final preview = ChatReplyPreview.fromSnapshot(
        ChatLastMessage.fromJson({
          'id': 5,
          'sender_id': 7,
          'type': 'image',
          'body': null,
          'media': [
            {
              'url': 'https://cdn.example/full.jpg',
              'thumbnail_url': 'https://cdn.example/thumb.jpg',
            },
          ],
        }),
      );
      expect(preview.text, '📷 Photo');
      expect(preview.thumbnailUrl, Uri.parse('https://cdn.example/thumb.jpg'));
      expect(preview.senderId, '7');
    });
  });

  group('quoted box', () {
    final quote = find.byKey(const ValueKey('chat-reply-quote-341'));
    final original = find.byKey(const ValueKey('300'));

    testWidgets('tapping scrolls to the original and flashes it', (
      tester,
    ) async {
      mockPlatform();
      await openChat(
        tester,
        LongRepo(
          replyTo: {
            'id': 300,
            'sender_id': 7,
            'type': 'text',
            'body': 'The original question',
          },
        ),
      );
      expect(
        find.descendant(of: quote, matching: find.text('Request Person')),
        findsOneWidget,
      );
      expect(original, findsNothing);
      await tester.tap(quote);
      await tester.pumpAndSettle();
      expect(original, findsOneWidget);
      final screen = tester.getRect(find.byType(ConversationScreen));
      final rect = tester.getRect(original);
      expect(rect.top, greaterThanOrEqualTo(screen.top));
      expect(rect.bottom, lessThanOrEqualTo(screen.bottom));
      Color? flash() =>
          (tester
                      .widget<AnimatedContainer>(
                        find.descendant(
                          of: original,
                          matching: find.byType(AnimatedContainer),
                        ),
                      )
                      .decoration
                  as BoxDecoration?)
              ?.color;
      expect(flash(), isNot(Colors.transparent));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(flash(), Colors.transparent);
    });

    testWidgets('loads older pages until the original is found', (
      tester,
    ) async {
      mockPlatform();
      final repo = LongRepo(
        paged: true,
        replyTo: {
          'id': 300,
          'sender_id': 7,
          'type': 'text',
          'body': 'The original question',
        },
      );
      await openChat(tester, repo);
      expect(repo.pages, isNot(contains('older')));
      await tester.tap(quote);
      await tester.pumpAndSettle();
      expect(repo.pages, contains('older'));
      expect(original, findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('a deleted original shows Message deleted and does nothing', (
      tester,
    ) async {
      mockPlatform();
      final repo = LongRepo(
        paged: true,
        replyTo: {
          'id': 300,
          'sender_id': 7,
          'type': 'text',
          'body': null,
          'is_deleted': true,
        },
      );
      await openChat(tester, repo);
      expect(
        find.descendant(of: quote, matching: find.text('Message deleted')),
        findsOneWidget,
      );
      final pages = repo.pages.length;
      final before = tester.getTopLeft(quote);
      await tester.tap(quote);
      await tester.pumpAndSettle();
      expect(repo.pages.length, pages);
      expect(tester.getTopLeft(quote), before);
      expect(original, findsNothing);
    });
  });
}
