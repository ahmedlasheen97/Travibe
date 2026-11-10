import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/features/chats/data/chat_broadcast_event.dart';
import 'package:travibe/features/chats/data/chat_models.dart';

Map<String, dynamic> messageEvent() => {
  'id': 101,
  'conversation_id': 42,
  'sender_id': 5,
  'type': 'text',
  'body': 'Fixture message',
  'is_deleted': false,
  'media': [],
  'read_at': null,
  'delivered_at': null,
  'updated_at': '2026-11-07T10:00:00Z',
};
void main() {
  test(
    'message.sent parses full MessageResource and has stable deduplication key',
    () {
      final a =
          ChatBroadcastEvent.parse('message.sent', messageEvent())
              as ChatMessageSent;
      final b =
          ChatBroadcastEvent.parse('message.sent', jsonEncode(messageEvent()))
              as ChatMessageSent;
      expect(a.message.id, '101');
      expect(a.key, b.key);
      expect(a.toString(), isNot(contains('Fixture message')));
    },
  );
  test('typing.updated uses exact documented boolean payload', () {
    final event =
        ChatBroadcastEvent.parse('typing.updated', {
              'conversation_id': 42,
              'user_id': 7,
              'is_typing': true,
            })
            as ChatTypingUpdated;
    expect(event.conversationId, '42');
    expect(event.userId, '7');
    expect(event.isTyping, true);
    expect(
      () => ChatBroadcastEvent.parse('typing.updated', {
        'conversation_id': 42,
        'user_id': 7,
        'is_typing': 'true',
      }),
      throwsFormatException,
    );
  });
  test('unknown event does not interpret routes or arbitrary payloads', () {
    expect(
      ChatBroadcastEvent.parse('arbitrary.route', {'route': '/admin'}),
      isNull,
    );
  });
  test('malformed supported events fail without private values', () {
    expect(
      () => ChatBroadcastEvent.parse('message.sent', {}),
      throwsFormatException,
    );
    expect(
      () => ChatBroadcastEvent.parse('typing.updated', 'invalid JSON'),
      throwsFormatException,
    );
  });
  test(
    'read receipt updates only own messages through cursor in matching thread',
    () {
      final event =
          ChatBroadcastEvent.parse('messages.read', {
                'conversation_id': 42,
                'reader_id': 7,
                'last_read_message_id': 101,
                'read_at': '2026-11-07T10:01:00Z',
              })
              as ChatMessagesRead;
      final items = [
        ChatMessage.fromJson(messageEvent()),
        ChatMessage.fromJson(messageEvent()..['id'] = 102),
        ChatMessage.fromJson(messageEvent()..['sender_id'] = 7),
        ChatMessage.fromJson(messageEvent()..['conversation_id'] = 43),
      ];
      final updated = event.apply(items, currentUserId: '5');
      expect(updated.first.delivery, ChatDelivery.seen);
      expect(
        updated.skip(1).every((m) => m.delivery == ChatDelivery.sent),
        true,
      );
    },
  );
  test('own read echo does not mark own outgoing messages seen', () {
    final event = ChatMessagesRead('42', '5', '101', DateTime.utc(2026, 11, 7));
    final message = ChatMessage.fromJson(messageEvent());
    expect(
      event.apply([message], currentUserId: '5').single.delivery,
      ChatDelivery.sent,
    );
  });
  test(
    'older duplicate read event cannot replace newer authoritative timestamp',
    () {
      final message = ChatMessage.fromJson(
        messageEvent()..['read_at'] = '2026-11-07T12:00:00Z',
      );
      final event = ChatMessagesRead(
        '42',
        '7',
        '101',
        DateTime.utc(2026, 11, 7, 10),
      );
      expect(
        event.apply([message], currentUserId: '5').single.readAt,
        DateTime.utc(2026, 11, 7, 12),
      );
    },
  );
}
