import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/chats/data/chat_repository.dart';
import 'package:travibe/features/shares/data/share_post_messenger.dart';
import 'send_post_fixtures.dart';

void main() {
  late RecordingChatRepository chat;
  late SharePostMessenger messenger;
  setUp(() {
    chat = RecordingChatRepository();
    messenger = SharePostMessenger(chat: chat);
  });

  test('starts or reuses a conversation and sends to each person', () async {
    final result = await messenger.send(
      post: sharedPost(),
      to: [person('2'), person('3')],
      note: '  Look at this!  ',
    );
    expect(chat.created, ['2', '3']);
    expect(chat.sent.map((s) => s.conversationId), ['c-2', 'c-3']);
    expect(
      chat.sent.first.text,
      'Look at this!\n\nShared a post by Sara: “Sunset over Petra”',
    );
    expect(result.sent.map((u) => u.id), ['2', '3']);
    expect(result.failed, isEmpty);
  });

  test('one failure does not stop the others; errors map per user', () async {
    chat.failures['2'] = ApiError(message: 'Forbidden', statusCode: 403);
    chat.failures['3'] = ChatUnconfirmedSend();
    chat.failures['4'] = ApiError(message: 'Account unavailable');
    chat.failures['5'] = StateError('boom');
    final result = await messenger.send(
      post: sharedPost(),
      to: [person('2'), person('3'), person('4'), person('5'), person('6')],
    );
    expect(result.sent.map((u) => u.id), ['6']);
    expect(result.failed, {
      '2': "You can't message Traveller 2.",
      '3': 'May not have been sent to Traveller 3.',
      '4': 'Account unavailable',
      '5': 'Unable to send. Please try again.',
    });
    expect(chat.sent.single.conversationId, 'c-6');
  });

  group('composeText', () {
    test('without a note or content', () {
      expect(
        SharePostMessenger.composeText(sharedPost(content: null), null),
        'Shared a post by Sara.',
      );
      expect(
        SharePostMessenger.composeText(sharedPost(content: '  '), '   '),
        'Shared a post by Sara.',
      );
    });

    test('collapses whitespace and clips long content', () {
      final text = SharePostMessenger.composeText(
        sharedPost(content: 'a\n\nb ${'x' * 400}'),
        null,
      );
      expect(text, startsWith('Shared a post by Sara: “a b x'));
      expect(text, endsWith('…”'));
      final excerpt = text.substring(
        text.indexOf('“') + 1,
        text.lastIndexOf('”'),
      );
      expect(excerpt.runes.length, SharePostMessenger.excerptLength);
    });

    test('never exceeds the chat body limit', () {
      final text = SharePostMessenger.composeText(sharedPost(), 'n' * 6000);
      expect(text.runes.length, SharePostMessenger.maxMessageLength);
    });
  });
}
