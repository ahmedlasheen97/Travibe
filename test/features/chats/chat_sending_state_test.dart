import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/chats/data/chat_media_selection.dart';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/screens/conversation_screen.dart';
import 'package:travibe/features/chats/widgets/chat_pending_media_bubble.dart';
import 'package:travibe/features/chats/widgets/chat_send_button.dart';
import 'package:travibe/features/chats/widgets/chat_widgets.dart';
import 'chat_badge_images_test.dart' show WaitingImageUpload;
import 'chat_fakes.dart';
import 'chat_interactions_test.dart' show png;
import 'chat_media_queue_send_test.dart' show MediaRepositoryFake;
import 'chat_widgets_test.dart' show harness;

/// Each text send waits on its own completer so tests control the order.
class QueuedSendRepo extends FakeChatRepository {
  QueuedSendRepo() {
    messageItems = [];
  }
  final texts = <String>[];
  final pending = <Completer<ChatMessage>>[];
  @override
  Future<ChatMessage> sendText(String id, String text) {
    sends++;
    texts.add(text);
    final completer = Completer<ChatMessage>();
    pending.add(completer);
    return completer.future;
  }

  void confirm(int index) => pending[index].complete(
    ChatMessage(
      id: '${100 + index}',
      senderId: 'self',
      conversationId: conversation.id,
      kind: ChatMessageKind.text,
      text: texts[index],
    ),
  );
}

Finder _inBubbles(Finder matching) =>
    find.descendant(of: find.byType(ChatMessageBubble), matching: matching);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('fixture');
  });

  testWidgets(
    'text send shows muted "Sending…" under the bubble, keeps the send button usable and sends in order',
    (tester) async {
      final repo = QueuedSendRepo();
      await tester.pumpWidget(
        harness(
          ConversationScreen(
            conversation: conversation,
            repository: repo,
            currentUserId: 'self',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'first');
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      await tester.pump();

      expect(find.text('Sending…'), findsOneWidget);
      final label = tester.widget<Text>(find.text('Sending…'));
      expect(label.style?.color, Colors.white54);
      expect(label.style?.fontSize, 12);
      expect(_inBubbles(find.byType(CupertinoActivityIndicator)), findsNothing);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).readOnly,
        isFalse,
      );

      // A second message can be typed and sent while the first is in flight.
      await tester.enterText(find.byType(TextField), 'second');
      await tester.pump();
      final send = tester.widget<IconButton>(
        find.descendant(
          of: find.byType(ChatSendButton),
          matching: find.byType(IconButton),
        ),
      );
      expect(send.onPressed, isNotNull);
      await tester.tap(find.byTooltip('Send message'));
      await tester.pump();
      expect(find.text('Sending…'), findsNWidgets(2));
      expect(repo.texts, ['first']); // Queued: one request at a time.

      repo.confirm(0);
      await tester.pumpAndSettle();
      expect(repo.texts, ['first', 'second']);
      expect(find.text('Sending…'), findsOneWidget);

      repo.confirm(1);
      await tester.pumpAndSettle();
      expect(find.text('Sending…'), findsNothing);
      expect(find.text('Failed to send. Tap to retry.'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('failed text send turns "Sending…" into the retry prompt', (
    tester,
  ) async {
    final repo = QueuedSendRepo();
    await tester.pumpWidget(
      harness(
        ConversationScreen(
          conversation: conversation,
          repository: repo,
          currentUserId: 'self',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'nope');
    await tester.pump();
    await tester.tap(find.byTooltip('Send message'));
    await tester.pump();
    expect(find.text('Sending…'), findsOneWidget);
    repo.pending.single.completeError(
      ApiError(message: 'Rejected', statusCode: 422),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sending…'), findsNothing);
    expect(find.text('Failed to send. Tap to retry.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final kind in [ChatMessageKind.image, ChatMessageKind.audio]) {
    testWidgets('pending ${kind.name} bubble: "Sending…" then retry prompt', (
      tester,
    ) async {
      var retries = 0;
      final media = ChatMediaSelection(
        png,
        kind == ChatMessageKind.image ? 'fixture.png' : 'recording.m4a',
        kind == ChatMessageKind.image ? 'image/png' : 'audio/mp4',
        kind,
        durationMs: kind == ChatMessageKind.audio ? 1200 : null,
      );
      Widget bubble(bool sending) => harness(
        Scaffold(
          body: ChatPendingMediaBubble(
            media: media,
            sending: sending,
            onRetry: () => retries++,
          ),
        ),
      );
      await tester.pumpWidget(bubble(true));
      await tester.pump();
      expect(find.text('Sending…'), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Failed to send. Tap to retry.'), findsNothing);

      await tester.pumpWidget(bubble(false));
      await tester.pump();
      expect(find.text('Sending…'), findsNothing);
      await tester.tap(find.text('Failed to send. Tap to retry.'));
      expect(retries, 1);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'while an image uploads the send button has no spinner and still sends text',
    (tester) async {
      final repo = MediaRepositoryFake()..failSecond = false;
      final upload = WaitingImageUpload();
      await tester.pumpWidget(
        harness(
          ConversationScreen(
            conversation: conversation,
            currentUserId: 'self',
            repository: repo,
            mediaUploader: upload,
            pickAttachments: (_) async => [
              XFile.fromData(png, name: 'fixture.png'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Attachments'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gallery'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Send attachments'));
      await tester.pump();

      expect(find.text('Sending…'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ChatSendButton),
          matching: find.byType(CupertinoActivityIndicator),
        ),
        findsNothing,
      );

      await tester.enterText(find.byType(TextField), 'meanwhile');
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      await tester.pump();
      expect(repo.sends, 1);

      upload.gate.complete();
      await tester.pumpAndSettle();
      expect(repo.sent, [101]);
      expect(find.text('Sending…'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      upload.close();
    },
  );
}
