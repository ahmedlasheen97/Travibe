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

  test('sends a post message, then the trimmed note as text', () async {
    final result = await messenger.send(
      post: sharedPost(),
      to: [person('2'), person('3')],
      note: '  Look at this!  ',
    );
    expect(chat.created, ['2', '3']);
    expect(chat.posts, [
      (conversationId: 'c-2', postId: 10),
      (conversationId: 'c-3', postId: 10),
    ]);
    expect(chat.sent.map((s) => s.text).toSet(), {'Look at this!'});
    expect(chat.calls.where((c) => c.endsWith('c-2')), [
      'post:c-2',
      'text:c-2',
    ]);
    expect(result.sent.map((u) => u.id), ['2', '3']);
    expect(result.failed, isEmpty);
    expect(result.noteFailed, isEmpty);
  });

  test('a blank note sends only the post', () async {
    await messenger.send(post: sharedPost(), to: [person('2')], note: '   ');
    expect(chat.calls, ['post:c-2']);
    expect(chat.sent, isEmpty);
  });

  test('one failure does not stop the others; errors map per user', () async {
    chat.failures['2'] = ApiError(message: 'Forbidden', statusCode: 403);
    chat.failures['3'] = ChatUnconfirmedSend();
    chat.failures['4'] = ApiError(message: 'Account unavailable');
    chat.failures['5'] = StateError('boom');
    chat.postFailures['c-7'] = ApiError(
      message: 'The message or request was not accepted.',
      statusCode: 422,
    );
    final result = await messenger.send(
      post: sharedPost(),
      to: [
        person('2'),
        person('3'),
        person('4'),
        person('5'),
        person('6'),
        person('7'),
      ],
      note: 'hi',
    );
    expect(result.sent.map((u) => u.id), ['6']);
    expect(result.failed, {
      '2': "You can't message Traveller 2.",
      '3': 'May not have been sent to Traveller 3.',
      '4': 'Account unavailable',
      '5': 'Unable to send. Please try again.',
      '7': "Traveller 7 can't see this post.",
    });
    expect(chat.posts.single.conversationId, 'c-6');
    // No note follows a post that was not accepted.
    expect(chat.calls.where((c) => c.endsWith('c-7')), ['post:c-7']);
  });

  test('a failed note still counts as sent so retry never reposts', () async {
    chat.noteFailures['c-2'] = ApiError(message: 'Network');
    final result = await messenger.send(
      post: sharedPost(),
      to: [person('2'), person('3')],
      note: 'hi',
    );
    expect(result.sent.map((u) => u.id), ['2', '3']);
    expect(result.failed, isEmpty);
    expect(result.noteFailed.map((u) => u.id), ['2']);
  });
}
