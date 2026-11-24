import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/screens/conversation_screen.dart';
import 'package:travibe/features/chats/widgets/chat_history_image.dart';
import 'package:travibe/features/chats/widgets/chat_widgets.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/screens/open_shared_story.dart';
import '../stories/story_viewer_test.dart' show viewerDetail, ViewerRepo;
import 'chat_fakes.dart';
import 'conversation_fixtures.dart';

final _future = DateTime.now().toUtc().add(const Duration(hours: 5));
final _past = DateTime.now().toUtc().subtract(const Duration(hours: 1));

Map<String, dynamic> storyCard({DateTime? expiresAt}) => {
  'id': 33,
  'user_id': 8,
  'thumbnail_url': 'https://cdn.example/s.jpg',
  'expires_at': (expiresAt ?? _future).toIso8601String(),
  'is_reshare': false,
};

Map<String, dynamic> storyReply({
  int senderId = 7,
  Object? story,
  DateTime? expiresAt,
  bool isStoryReply = true,
  String updatedAt = '2026-11-21T09:00:00Z',
}) => {
  'id': 601,
  'conversation_id': 42,
  'sender_id': senderId,
  'type': 'text',
  'body': 'Love this!',
  'media': <Object>[],
  'post_id': null,
  'post': null,
  'story': story,
  'story_expires_at': isStoryReply
      ? (expiresAt ?? _future).toIso8601String()
      : null,
  'poster': null,
  'reply_to': null,
  'duration_ms': null,
  'is_deleted': false,
  'delivered_at': null,
  'read_at': null,
  'created_at': '2026-11-21T09:00:00Z',
  'updated_at': updatedAt,
  'deleted_at': null,
};

void main() {
  group('parsing', () {
    test('a story reply carries the card and story_expires_at', () {
      final message = ChatMessage.fromJson(storyReply(story: storyCard()));
      expect(message.kind, ChatMessageKind.text);
      expect(message.isStoryReply, isTrue);
      final card = message.story!;
      expect(card.id, '33');
      expect(card.userId, '8');
      expect(card.thumbnailUrl, Uri.parse('https://cdn.example/s.jpg'));
      expect(card.isReshare, isFalse);
      expect(message.storyAvailable(DateTime.now()), isTrue);
    });

    test('availability: null card or passed expiry is unavailable', () {
      final gone = ChatMessage.fromJson(storyReply());
      expect(gone.isStoryReply, isTrue);
      expect(gone.storyAvailable(DateTime.now()), isFalse);
      final expired = ChatMessage.fromJson(
        storyReply(
          story: storyCard(expiresAt: _past),
          expiresAt: _past,
        ),
      );
      expect(expired.storyAvailable(DateTime.now()), isFalse);
    });

    test('ordinary messages are not story replies', () {
      final message = ChatMessage.fromJson(storyReply(isStoryReply: false));
      expect(message.isStoryReply, isFalse);
      expect(message.story, isNull);
    });

    test('updated_since replacement keeps the incoming story fields', () {
      final old = ChatMessage.fromJson(storyReply(story: storyCard()));
      final gone = ChatMessage.fromJson(
        storyReply(updatedAt: '2026-11-21T10:00:00Z'),
      );
      final merged = reconcileChatMessage(old, gone);
      expect(merged.story, isNull);
      expect(merged.isStoryReply, isTrue);
    });

    test('inbox preview depends on who replied', () {
      // conversationJson's other user is id 7.
      ChatConversation inbox(int sender) => ChatConversation.fromJson(
        conversationJson()
          ..['last_message'] = storyReply(senderId: sender, story: storyCard()),
      );
      expect(inbox(7).preview, 'Replied to your story');
      expect(inbox(99).preview, 'You replied to their story');
    });
  });

  group('bubble', () {
    Future<void> pump(
      WidgetTester tester,
      ChatMessage message, {
      bool outgoing = false,
    }) => tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          home: Scaffold(
            body: ChatMessageBubble(message: message, outgoing: outgoing),
          ),
        ),
      ),
    );

    testWidgets('owner sees "Replied to your story" with the thumbnail', (
      tester,
    ) async {
      await pump(tester, ChatMessage.fromJson(storyReply(story: storyCard())));
      expect(find.text('Replied to your story'), findsOneWidget);
      expect(find.text('Love this!'), findsOneWidget);
      expect(find.byType(ChatHistoryImage), findsOneWidget);
    });

    for (final outgoing in [false, true]) {
      testWidgets(
        'label, portrait thumbnail, then the message bubble; outgoing=$outgoing',
        (tester) async {
          await pump(
            tester,
            ChatMessage.fromJson(storyReply(story: storyCard())),
            outgoing: outgoing,
          );
          final label = find.text(
            outgoing ? 'You replied to their story' : 'Replied to your story',
          );
          final thumb = find.byType(ChatHistoryImage);
          final body = find.text('Love this!');
          expect(tester.getSize(thumb), const Size(110, 160));
          expect(
            tester.getBottomLeft(label).dy,
            lessThanOrEqualTo(tester.getTopLeft(thumb).dy),
          );
          expect(
            tester.getBottomLeft(thumb).dy,
            lessThan(tester.getTopLeft(body).dy),
          );
          // Label sits outside the message bubble.
          expect(
            find.ancestor(of: label, matching: find.byType(GestureDetector)),
            findsNothing,
          );
          final width = tester.getSize(find.byType(Scaffold)).width;
          if (outgoing) {
            expect(tester.getTopRight(thumb).dx, greaterThan(width / 2));
            expect(tester.getTopLeft(thumb).dx, greaterThan(width / 2));
          } else {
            expect(tester.getTopRight(thumb).dx, lessThan(width / 2));
          }
        },
      );
    }

    testWidgets('unavailable story: label above the bubble, no thumbnail', (
      tester,
    ) async {
      await pump(tester, ChatMessage.fromJson(storyReply()));
      expect(find.byType(ChatHistoryImage), findsNothing);
      expect(
        tester.getBottomLeft(find.text('Story unavailable')).dy,
        lessThan(tester.getTopLeft(find.text('Love this!')).dy),
      );
      expect(find.byIcon(Icons.hide_image_outlined), findsNothing);
    });

    testWidgets('replier sees "You replied to their story"', (tester) async {
      await pump(
        tester,
        ChatMessage.fromJson(storyReply(story: storyCard())),
        outgoing: true,
      );
      expect(find.text('You replied to their story'), findsOneWidget);
    });

    for (final outgoing in [true, false]) {
      testWidgets('gone or expired story is unavailable; outgoing=$outgoing', (
        tester,
      ) async {
        await pump(
          tester,
          ChatMessage.fromJson(storyReply()),
          outgoing: outgoing,
        );
        expect(find.text('Story unavailable'), findsOneWidget);
        expect(find.byType(ChatHistoryImage), findsNothing);
        await pump(
          tester,
          ChatMessage.fromJson(
            storyReply(
              story: storyCard(expiresAt: _past),
              expiresAt: _past,
            ),
          ),
          outgoing: outgoing,
        );
        expect(find.text('Story unavailable'), findsOneWidget);
        expect(find.byType(ChatHistoryImage), findsNothing);
      });
    }

    testWidgets('ordinary messages have no story label', (tester) async {
      await pump(tester, ChatMessage.fromJson(storyReply(isStoryReply: false)));
      expect(find.textContaining('story'), findsNothing);
      expect(find.text('Story unavailable'), findsNothing);
    });
  });

  group('opening the story', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await PreferencesManager().init();
      await PreferencesManager().saveToken('story-open-test');
    });
    tearDown(() async => PreferencesManager().clear());

    Future<void> pumpBubble(
      WidgetTester tester,
      ChatMessage message, {
      void Function(int)? onOpen,
      Set<String> gone = const {},
    }) => tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          home: Scaffold(
            body: ChatMessageBubble(
              message: message,
              outgoing: false,
              onOpenStory: onOpen,
              unavailableStoryIds: gone,
            ),
          ),
        ),
      ),
    );
    final thumbnail = find.byKey(const ValueKey('chat-story-thumbnail-601'));

    testWidgets('tapping the thumbnail opens that story', (tester) async {
      final opened = <int>[];
      await pumpBubble(
        tester,
        ChatMessage.fromJson(storyReply(story: storyCard())),
        onOpen: opened.add,
      );
      await tester.tap(thumbnail);
      expect(opened, [33]);
    });

    testWidgets('a story found gone shows as unavailable, not tappable', (
      tester,
    ) async {
      await pumpBubble(
        tester,
        ChatMessage.fromJson(storyReply(story: storyCard())),
        gone: {'33'},
      );
      expect(find.text('Story unavailable'), findsOneWidget);
      expect(thumbnail, findsNothing);
    });

    Future<List<String>> openWith(
      WidgetTester tester,
      SharedStoryLoader? load, {
      List<Route<dynamic>>? pushed,
      StoriesRepo? stories,
    }) async {
      final gone = <String>[];
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            navigatorObservers: [if (pushed != null) _Pushes(pushed)],
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => openSharedStory(
                    context,
                    33,
                    load: load,
                    stories: stories,
                    onUnavailable: () => gone.add('33'),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump();
      return gone;
    }

    for (final status in [403, 404]) {
      testWidgets('HTTP $status: "Story unavailable" toast and callback', (
        tester,
      ) async {
        final gone = await openWith(
          tester,
          (_) async => throw ApiError(message: 'x', statusCode: status),
        );
        expect(find.text(sharedStoryUnavailable), findsOneWidget);
        expect(gone, ['33']);
        await tester.pumpAndSettle(const Duration(seconds: 5));
      });
    }

    testWidgets('an expired story is unavailable too', (tester) async {
      final gone = await openWith(
        tester,
        (id) async => StoryDetail.fromJson(
          viewerDetail(id)..['expires_at'] = _past.toIso8601String(),
        ),
      );
      expect(find.text(sharedStoryUnavailable), findsOneWidget);
      expect(gone, ['33']);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('offline shows the error and keeps the story available', (
      tester,
    ) async {
      final gone = await openWith(
        tester,
        (_) async => throw ApiError(message: 'No internet connection.'),
      );
      expect(find.text('No internet connection.'), findsOneWidget);
      expect(find.text(sharedStoryUnavailable), findsNothing);
      expect(gone, isEmpty);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('a live story opens the single-story viewer', (tester) async {
      final pushed = <Route<dynamic>>[];
      // ViewerRepo loads viewerDetail and records views without network.
      final gone = await openWith(
        tester,
        null,
        pushed: pushed,
        stories: ViewerRepo(),
      );
      expect(gone, isEmpty);
      expect(pushed.last.settings.name, 'story/33');
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('conversation', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await PreferencesManager().init();
      await PreferencesManager().saveToken('story-conversation-test');
    });
    tearDown(() async => PreferencesManager().clear());

    Future<void> pumpConversation(
      WidgetTester tester,
      ChatMessage reply, {
      required DateTime Function() now,
      SharedStoryLoader? load,
    }) async {
      final repo = FakeChatRepository()..messageItems = [reply];
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            home: ConversationScreen(
              repository: repo,
              conversation: conversation,
              currentUserId: 'self',
              loadStory: load,
              now: now,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('label flips to "Story unavailable" at story_expires_at', (
      tester,
    ) async {
      final base = DateTime.now().toUtc();
      var clock = base;
      final expires = base.add(const Duration(seconds: 30));
      await pumpConversation(
        tester,
        ChatMessage.fromJson(
          storyReply(
            senderId: 7,
            story: storyCard(expiresAt: expires),
            expiresAt: expires,
          ),
        ),
        now: () => clock,
      );
      expect(find.text('Replied to your story'), findsOneWidget);
      // Time passes with no event, fetch or interaction.
      clock = expires.add(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('Replied to your story'), findsOneWidget);
      await tester.pump(const Duration(seconds: 31));
      expect(find.text('Story unavailable'), findsOneWidget);
      expect(find.text('Replied to your story'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a tapped story that is gone updates the bubble', (
      tester,
    ) async {
      final loads = <int>[];
      await pumpConversation(
        tester,
        ChatMessage.fromJson(storyReply(senderId: 7, story: storyCard())),
        now: DateTime.now,
        load: (id) async {
          loads.add(id);
          throw ApiError(message: 'Not found', statusCode: 404);
        },
      );
      expect(find.text('Replied to your story'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-story-thumbnail-601')));
      await tester.pump();
      await tester.pump();
      expect(loads, [33]);
      // Toast and bubble label.
      expect(find.text('Story unavailable'), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('chat-story-thumbnail-601')),
        findsNothing,
      );
      await tester.pumpAndSettle(const Duration(seconds: 5));
      await tester.pumpWidget(const SizedBox());
    });
  });
}

class _Pushes extends NavigatorObserver {
  _Pushes(this.routes);
  final List<Route<dynamic>> routes;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.add(route);
}
