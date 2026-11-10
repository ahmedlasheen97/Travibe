import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/data/laravel_conversation_contract.dart';

import 'conversation_fixtures.dart';

void main() {
  const contract = LaravelConversationContract();
  test('full conversation resource parses stable IDs and preview', () {
    final item = contract.decodeConversation({'data': conversationJson()});
    expect(item.id, '42');
    expect(item.participant.id, '7');
    expect(item.preview, 'Fixture preview');
    expect(item.unread, 2);
    expect(item.isMuted, false);
    expect(item.isBlocked, false);
    expect(item.isAccepted, false);
    expect(item.acceptedAt, isNull);
    expect(item.canSend, false);
    expect(item.createdAt, DateTime.utc(2026, 11, 6, 9));
    expect(item.lastMessageAt, DateTime.utc(2026, 11, 7, 9));
    expect(item.updatedAt, isNull);
    expect(item.participant.username, 'fixture');
    expect(item.participant.countryCode, 'EG');
    expect(item.participant.isFollowing, true);
    expect(item.participant.followsYou, false);
    expect(item.participant.followersCount, 3);
    expect(item.participant.followingCount, 4);
  });
  test(
    'last message preserves supplied fields alongside verified message APIs',
    () {
      final json = conversationJson();
      final last = json['last_message'] as Map;
      last['duration_ms'] = 1600;
      last['read_at'] = '2026-11-07T09:05:00Z';
      last['delivered_at'] = '2026-11-07T09:01:00Z';
      last['media'] = [
        {'fixture': 'opaque'},
      ];
      last['poster'] = {'fixture': 1};
      last['reply_to'] = {'id': 100};
      final item = ChatConversation.fromJson(json).lastMessage!;
      expect(item.id, '101');
      expect(item.senderId, '7');
      expect(item.conversationId, '42');
      expect(item.type, 'unconfirmed-type');
      expect(item.durationMs, 1600);
      expect(item.readAt, DateTime.utc(2026, 11, 7, 9, 5));
      expect(item.deliveredAt, DateTime.utc(2026, 11, 7, 9, 1));
      expect(() => (item.media as List).add('change'), throwsUnsupportedError);
      expect(() => (item.poster as Map)['fixture'] = 2, throwsUnsupportedError);
      expect(contract.capabilities.messages, true);
      expect(contract.capabilities.sendText, true);
    },
  );
  test('null related resources are safe and are not invented identities', () {
    final json = conversationJson()
      ..['other_user'] = null
      ..['last_message'] = null
      ..['unread_count'] = null;
    final item = ChatConversation.fromJson(json);
    expect(item.participant.id, '');
    expect(item.participant.name, 'Unavailable user');
    expect(item.preview, '');
    expect(item.lastMessage, isNull);
    expect(item.unread, 0);
  });
  test('only ID is required when optional fields are omitted', () {
    final item = ChatConversation.fromJson({'id': '42'});
    expect(item.id, '42');
    expect(item.lastMessage, isNull);
    expect(item.isAccepted, isNull);
    expect(item.isBlocked, isNull);
  });
  test('deleted last-message body is not exposed as preview', () {
    final json = conversationJson();
    (json['last_message'] as Map)['is_deleted'] = true;
    expect(ChatConversation.fromJson(json).preview, '');
  });
  for (final raw in [
    'online',
    'offline',
    'true',
    'false',
    '1',
    '0',
    'unknown-value',
  ]) {
    test(
      'online string $raw remains unclassified pending enum confirmation',
      () {
        final user = ChatParticipant.fromJson({
          'id': 7,
          'name': 'Fixture',
          'is_online': raw,
        });
        expect(user.onlineStatus, raw);
        expect(user.online, isNull);
      },
    );
  }
  test('nullable accepted and read IDs retain authoritative values', () {
    final json = conversationJson()
      ..['accepted_at'] = '2026-11-07T08:00:00Z'
      ..['is_accepted'] = true
      ..['last_read_message_id'] = 100;
    final item = ChatConversation.fromJson(json);
    expect(item.isAccepted, true);
    expect(item.acceptedAt, DateTime.utc(2026, 11, 7, 8));
    expect(item.lastReadMessageId, '100');
    expect(item.canSend, true);
  });
  test('empty and non-empty lists parse with the same contract', () {
    expect(
      contract.decodeConversations(conversationPage()).items.single.id,
      '42',
    );
    expect(
      contract.decodeConversations(conversationPage(items: [], total: 0)).items,
      isEmpty,
    );
  });
  test('page continuation and authoritative total survive partial pages', () {
    final page = contract.decodeConversations(
      conversationPage(last: 3, total: 31),
    );
    expect(page.continuation, '2');
    expect(page.total, 31);
    expect(contract.pagination(page.continuation), {'page': 2});
    expect(
      contract
          .decodeConversations(conversationPage(page: 3, last: 3, total: 31))
          .continuation,
      isNull,
    );
  });
  test('pagination never follows server-provided URLs', () {
    final json = conversationPage(last: 2, total: 2);
    json['links'] = {'next': 'https://untrusted.invalid/private'};
    expect(
      contract.pagination(contract.decodeConversations(json).continuation),
      {'page': 2},
    );
  });
  test(
    'missing pagination is an error rather than a fake successful empty page',
    () {
      expect(
        () => contract.decodeConversations({'data': []}),
        throwsA(isA<ApiError>()),
      );
    },
  );
  test('malformed records are rejected without dropping individual rows', () {
    for (final invalid in [
      null,
      {'other_user': null},
      {'id': 42, 'unread_count': -1},
      {'id': 42, 'last_message': 'bad'},
      {'id': 42, 'created_at': 'bad'},
    ]) {
      expect(
        () => contract.decodeConversations(conversationPage(items: [invalid])),
        throwsA(isA<ApiError>()),
      );
    }
  });
  test('creation uses exactly the confirmed user_id field', () {
    expect(contract.creationBody('7'), {'user_id': 7});
  });
  test('missing or malformed creation ID cannot reach HTTP', () {
    for (final id in ['', ' ', '../7']) {
      expect(() => contract.creationBody(id), throwsFormatException);
    }
  });
  test('authorized contract enables verified mutations and text bodies', () {
    expect(contract.capabilities.read, true);
    expect(contract.capabilities.remove, true);
    expect(contract.capabilities.requestActions, true);
    expect(contract.readBody(), isNull);
    expect(contract.requestActionBody(accept: true), isNull);
    expect(contract.textBody('hello'), {'type': 'text', 'body': 'hello'});
  });
}
