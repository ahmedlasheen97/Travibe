import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/data/chat_repository.dart';
import 'package:travibe/features/chats/widgets/chat_history_image.dart';
import 'package:travibe/features/chats/widgets/chat_post_card.dart';
import 'package:travibe/features/chats/widgets/chat_widgets.dart';
import 'conversation_fixtures.dart';

Map<String, dynamic> postCard({
  int id = 4,
  String? content = 'Sunset over Petra',
  List<Map<String, dynamic>> media = const [],
  String createdAt = '2026-11-10T09:00:00Z',
}) => {
  'id': id,
  'user': {'id': 2, 'name': 'Sara', 'avatar_url': null},
  'content': content,
  'media': media,
  'url': 'https://travibeapp.com/p/$id',
  'created_at': createdAt,
};

Map<String, dynamic> postMessage({
  Object? post,
  int postId = 4,
  String updatedAt = '2026-11-11T09:00:00Z',
}) => {
  'id': 501,
  'conversation_id': 42,
  'sender_id': 7,
  'type': 'post',
  'body': null,
  'media': <Object>[],
  'post_id': postId,
  'post': post,
  'poster': null,
  'reply_to': null,
  'duration_ms': null,
  'is_deleted': false,
  'delivered_at': null,
  'read_at': null,
  'created_at': '2026-11-11T09:00:00Z',
  'updated_at': updatedAt,
  'deleted_at': null,
};

class _Adapter implements HttpClientAdapter {
  int status = 201;
  Object? responseData;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(responseData),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('parsing', () {
    test('post messages carry post_id and the card', () {
      final message = ChatMessage.fromJson(
        postMessage(
          post: postCard(
            media: [
              {'id': 9, 'url': 'https://cdn.example/p.jpg'},
            ],
          ),
        ),
      );
      expect(message.kind, ChatMessageKind.post);
      expect(message.postId, '4');
      final card = message.sharedPost!;
      expect(card.id, '4');
      expect(card.author.name, 'Sara');
      expect(card.content, 'Sunset over Petra');
      expect(card.imageUrl, Uri.parse('https://cdn.example/p.jpg'));
      expect(card.url, Uri.parse('https://travibeapp.com/p/4'));
      expect(card.createdAt, DateTime.utc(2026, 11, 10, 9));
    });

    test('a null card keeps post_id for the unavailable state', () {
      final message = ChatMessage.fromJson(postMessage());
      expect(message.kind, ChatMessageKind.post);
      expect(message.postId, '4');
      expect(message.sharedPost, isNull);
    });

    test('non-https card links are dropped', () {
      final card = ChatSharedPost.tryParse({
        ...postCard(
          media: [
            {'url': 'http://cdn.example/p.jpg'},
          ],
        ),
        'url': 'travibe://posts/4',
      })!;
      expect(card.imageUrl, isNull);
      expect(card.url, isNull);
    });

    test('inbox preview says "Shared a post" and keeps the card', () {
      final json = conversationJson()
        ..['last_message'] = postMessage(post: postCard());
      final conversation = ChatConversation.fromJson(json);
      expect(conversation.preview, 'Shared a post');
      expect(conversation.lastMessage!.postId, '4');
      expect(conversation.lastMessage!.sharedPost!.author.name, 'Sara');
    });
  });

  group('updated_since replacement', () {
    test('a changed card replaces the old one at the same updated_at', () {
      final old = ChatMessage.fromJson(postMessage(post: postCard()));
      final edited = ChatMessage.fromJson(
        postMessage(post: postCard(content: 'Edited caption')),
      );
      final merged = reconcileChatMessage(old, edited);
      expect(merged.sharedPost!.content, 'Edited caption');
    });

    test('a card that becomes unavailable replaces the old one', () {
      final old = ChatMessage.fromJson(postMessage(post: postCard()));
      final gone = ChatMessage.fromJson(
        postMessage(updatedAt: '2026-11-11T10:00:00Z'),
      );
      final merged = reconcileChatMessage(old, gone);
      expect(merged.sharedPost, isNull);
      expect(merged.postId, '4');
    });
  });

  group('sendPost', () {
    final preferences = PreferencesManager();
    late _Adapter adapter;
    late LaravelChatRepository repo;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await preferences.init();
      await preferences.saveToken('fixture-session');
      adapter = _Adapter();
      repo = LaravelChatRepository(
        dio: Dio(BaseOptions(baseUrl: 'https://example.invalid/api/v1/'))
          ..httpClientAdapter = adapter,
      );
    });

    test('posts type: post with post_id only', () async {
      adapter.responseData = {'data': postMessage(post: postCard())};
      final sent = await repo.sendPost('42', 4);
      expect(adapter.requests.single.method, 'POST');
      expect(adapter.requests.single.path, 'conversations/42/messages');
      expect(adapter.requests.single.data, {'type': 'post', 'post_id': 4});
      expect(sent.kind, ChatMessageKind.post);
      expect(sent.sharedPost!.id, '4');
    });

    test('422 surfaces as an ApiError with the status', () async {
      adapter
        ..status = 422
        ..responseData = {
          'errors': {
            'post_id': ['hidden'],
          },
        };
      await expectLater(
        repo.sendPost('42', 4),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'status', 422)),
      );
    });
  });

  group('bubble', () {
    Future<void> pump(
      WidgetTester tester,
      ChatMessage message, {
      void Function(int)? onOpen,
      bool outgoing = false,
    }) => tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          home: Scaffold(
            body: ChatMessageBubble(
              message: message,
              outgoing: outgoing,
              onOpenPost: onOpen,
            ),
          ),
        ),
      ),
    );

    testWidgets('renders the card and opens the post on tap', (tester) async {
      final semantics = tester.ensureSemantics();
      final opened = <int>[];
      await pump(
        tester,
        ChatMessage.fromJson(
          postMessage(post: postCard(content: 'Line one\nLine two')),
        ),
        onOpen: opened.add,
      );
      expect(find.text('Sara'), findsOneWidget);
      expect(find.text('Line one\nLine two'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Shared post by Sara. Open post'),
        findsOneWidget,
      );
      semantics.dispose();
      await tester.tap(find.text('Sara'));
      expect(opened, [4]);
    });

    testWidgets('unavailable posts are labelled and not tappable', (
      tester,
    ) async {
      final opened = <int>[];
      await pump(
        tester,
        ChatMessage.fromJson(postMessage()),
        onOpen: opened.add,
      );
      expect(find.text('Post unavailable'), findsOneWidget);
      await tester.tap(find.text('Post unavailable'));
      expect(opened, isEmpty);
    });

    BoxDecoration frameOf(WidgetTester tester) =>
        tester
                .widgetList<Container>(
                  find.descendant(
                    of: find.byType(ChatMessageBubble),
                    matching: find.byType(Container),
                  ),
                )
                .firstWhere((c) => c.decoration is BoxDecoration)
                .decoration!
            as BoxDecoration;

    testWidgets('header shows the author and relative post time', (
      tester,
    ) async {
      final created = DateTime.now().toUtc().subtract(
        const Duration(minutes: 20, seconds: 5),
      );
      await pump(
        tester,
        ChatMessage.fromJson(
          postMessage(post: postCard(createdAt: created.toIso8601String())),
        ),
      );
      expect(find.text('Sara'), findsOneWidget);
      expect(find.text('20min'), findsOneWidget);
    });

    testWidgets('long text is capped at three lines with an ellipsis', (
      tester,
    ) async {
      await pump(
        tester,
        ChatMessage.fromJson(postMessage(post: postCard(content: 'x ' * 400))),
      );
      final text = tester.widget<Text>(
        find.descendant(
          of: find.byType(ChatPostCard),
          matching: find.textContaining('x x'),
        ),
      );
      expect(text.maxLines, 3);
      expect(text.overflow, TextOverflow.ellipsis);
    });

    testWidgets('first image spans the card; text-only posts have none', (
      tester,
    ) async {
      await pump(
        tester,
        ChatMessage.fromJson(
          postMessage(
            post: postCard(
              media: [
                {'id': 9, 'url': 'https://cdn.example/p.jpg'},
              ],
            ),
          ),
        ),
      );
      final image = tester.widget<ChatHistoryImage>(
        find.byType(ChatHistoryImage),
      );
      expect(image.width, ChatPostCard.imageWidth);
      expect(image.maxHeight, ChatPostCard.imageMaxHeight);
      expect(
        tester.getSize(find.byType(ChatHistoryImage)).width,
        ChatPostCard.imageWidth,
      );

      await pump(tester, ChatMessage.fromJson(postMessage(post: postCard())));
      expect(find.byType(ChatHistoryImage), findsNothing);
      expect(find.text('Sunset over Petra'), findsOneWidget);
    });

    for (final outgoing in [true, false]) {
      testWidgets('post frame is grey, never orange; outgoing=$outgoing', (
        tester,
      ) async {
        await pump(
          tester,
          ChatMessage.fromJson(postMessage(post: postCard())),
          outgoing: outgoing,
        );
        expect(frameOf(tester).color, const Color(0xFF2C2C2C));
        final frame = tester
            .widgetList<Container>(
              find.descendant(
                of: find.byType(ChatMessageBubble),
                matching: find.byType(Container),
              ),
            )
            .firstWhere((c) => c.decoration is BoxDecoration);
        expect(frame.padding, EdgeInsets.all(AppSizes.adaptiveWidth(8)));
        final card = tester.getRect(find.byType(ChatPostCard));
        final screen = tester.getRect(find.byType(Scaffold));
        if (outgoing) {
          expect(card.right, greaterThan(screen.center.dx));
          expect(card.left, greaterThan(screen.left + 16));
        } else {
          expect(card.left, lessThan(screen.center.dx));
          expect(card.right, lessThan(screen.right - 16));
        }
      });
    }

    testWidgets('reply snippets to a post read "Shared a post"', (
      tester,
    ) async {
      await pump(
        tester,
        ChatMessage.fromJson({
          ...postMessage(),
          'id': 502,
          'type': 'text',
          'body': 'Nice',
          'post_id': null,
          'reply_to': postMessage(post: postCard()),
        }),
      );
      expect(find.text('Shared a post'), findsOneWidget);
    });
  });
}
