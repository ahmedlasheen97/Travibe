import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/dio_client.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/data/chat_repository.dart';
import 'conversation_fixtures.dart';

Map<String, dynamic> messageJson({
  String type = 'text',
  bool deleted = false,
  String? delivered,
  String? read,
}) => {
  'id': 101,
  'conversation_id': 42,
  'sender_id': 5,
  'type': type,
  'body': deleted ? null : 'Fixture message',
  'media': deleted
      ? []
      : [
          if (type != 'text')
            {
              'id': 19,
              'url': 'https://example.invalid/media',
              'thumbnail_url': null,
              'mime_type': null,
              'width': null,
              'height': null,
            },
        ],
  'poster': {},
  'reply_to': null,
  'duration_ms': type == 'voice' ? 1600 : null,
  'is_deleted': deleted,
  'delivered_at': delivered,
  'read_at': read,
  'created_at': deleted ? null : '2026-11-07T12:00:00Z',
  'updated_at': '2026-11-07T12:01:00Z',
  'deleted_at': deleted ? '2026-11-07T12:01:00Z' : null,
};

class _Api implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final wireBodies = <String?>[];
  Object? response;
  int? status;
  Completer<void>? pending;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    wireBodies.add(
      requestStream == null
          ? null
          : utf8.decode(
              await requestStream.fold<List<int>>(
                [],
                (all, chunk) => all..addAll(chunk),
              ),
            ),
    );
    if (pending != null) await pending!.future;
    Object? data = response;
    if (data == null) {
      if (options.path.endsWith('/messages')) {
        data = options.method == 'POST'
            ? {'data': messageJson()}
            : {
                'data': [messageJson()],
                'meta': {'current_page': 1, 'last_page': 2, 'total': 20},
              };
      } else if (options.path.endsWith('/accept')) {
        data = {'data': conversationJson()..['is_accepted'] = true};
      } else if (options.path == 'broadcasting/auth') {
        data = {'auth': 'fixture-signature', 'channel_data': '{}'};
      } else if (options.method == 'DELETE' ||
          options.path.endsWith('/decline') ||
          options.path.endsWith('/typing')) {
        data = {'message': 'Confirmed'};
      } else if (options.path == 'conversations' ||
          options.path == 'conversations/requests') {
        data = conversationPage();
      } else {
        data = {'data': conversationJson()};
      }
    }
    return ResponseBody.fromString(
      jsonEncode(data),
      status ??
          (options.method == 'POST' && options.path.endsWith('/messages')
              ? 201
              : 200),
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final prefs = PreferencesManager();
  late _Api api;
  late LaravelChatRepository repo;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await prefs.init();
    await prefs.saveToken('test-session');
    api = _Api();
    final client = DioClient();
    client.dio.httpClientAdapter = api;
    repo = LaravelChatRepository(dio: client.dio);
    addTearDown(() => client.dio.close(force: true));
  });
  test(
    'inbox and requests use documented server search with page pagination',
    () async {
      await repo.searchConversations(' traveler ', continuation: '2');
      expect(api.requests.last.path, 'conversations');
      expect(
        api.requests.last.queryParameters,
        containsPair('search', 'traveler'),
      );
      expect(api.requests.last.queryParameters, containsPair('page', 2));
      await repo.searchConversations('fixture', requests: true);
      expect(api.requests.last.path, 'conversations/requests');
      expect(
        api.requests.last.queryParameters,
        containsPair('search', 'fixture'),
      );
      await expectLater(
        repo.searchConversations('x' * 101),
        throwsArgumentError,
      );
      expect(api.requests, hasLength(2));
    },
  );
  test('mute PATCH sends only is_muted and parses updated header', () async {
    await repo.setMuted('42', true);
    expect(api.requests.single.method, 'PATCH');
    expect(api.requests.single.data, {'is_muted': true});
  });
  test('remove uses documented 200 confirmation, not assumed 204', () async {
    await repo.remove('42');
    expect(api.requests.single.method, 'DELETE');
    api.status = 204;
    await expectLater(repo.remove('42'), throwsA(isA<ApiError>()));
  });
  test(
    'read has no body and returns authoritative unread/header state',
    () async {
      final json = conversationJson()
        ..['unread_count'] = 0
        ..['last_read_message_id'] = 101;
      api.response = {'data': json};
      final result = await repo.readConversation('42');
      expect(result.unread, 0);
      expect(result.lastReadMessageId, '101');
      expect(api.requests.single.data, isNull);
    },
  );
  test('typing sends required boolean and supports explicit stop', () async {
    await repo.typing('42', true);
    await repo.typing('42', false);
    expect(api.requests.map((r) => r.data), [
      {'is_typing': true},
      {'is_typing': false},
    ]);
  });
  test(
    'accept parses header; decline parses confirmation with no request body',
    () async {
      await repo.resolveRequest('42', accept: true);
      await repo.resolveRequest('42', accept: false);
      expect(api.requests.map((r) => r.path), [
        'conversations/42/accept',
        'conversations/42/decline',
      ]);
      expect(api.requests.every((r) => r.data == null), true);
    },
  );
  test('text sends confirmed enum/body and requires 201 resource', () async {
    final message = await repo.sendText('42', 'Hello 😀');
    expect(api.requests.single.data, {'type': 'text', 'body': 'Hello 😀'});
    expect(message.id, '101');
    expect(message.delivery, ChatDelivery.sent);
    api.status = 200;
    await expectLater(repo.sendText('42', 'Hello'), throwsA(isA<ApiError>()));
  });
  test('text limits reject empty and overlong bodies before HTTP', () async {
    await expectLater(repo.sendText('42', ' '), throwsA(isA<ApiError>()));
    await expectLater(
      repo.sendText('42', List.filled(5001, 'a').join()),
      throwsA(isA<ApiError>()),
    );
    expect(api.requests, isEmpty);
  });
  test('replies use reply_to_id without changing the endpoint', () async {
    await repo.reply('42', 'Reply', '100');
    expect(api.requests.single.data, {
      'type': 'text',
      'body': 'Reply',
      'reply_to_id': 100,
    });
  });
  test('image media sends ready media id and optional caption', () async {
    await repo.sendMedia(
      '42',
      kind: ChatMessageKind.image,
      mediaId: 19,
      caption: 'Caption',
    );
    expect(api.requests.single.data, {
      'type': 'image',
      'media_id': 19,
      'body': 'Caption',
    });
  });
  test('voice sends media id and required duration with no body', () async {
    await repo.sendMedia(
      '42',
      kind: ChatMessageKind.audio,
      mediaId: 19,
      durationMs: 1600,
    );
    expect(api.requests.single.data, {
      'type': 'voice',
      'media_id': 19,
      'duration_ms': 1600,
    });
  });
  test(
    'video send supports documented poster/duration and no caption',
    () async {
      await repo.sendMedia(
        '42',
        kind: ChatMessageKind.video,
        mediaId: 19,
        posterMediaId: 20,
        durationMs: 3000,
      );
      expect(api.requests.single.data, {
        'type': 'video',
        'media_id': 19,
        'poster_media_id': 20,
        'duration_ms': 3000,
      });
    },
  );
  test('invalid attachment combinations never reach network', () async {
    await expectLater(
      repo.sendMedia('42', kind: ChatMessageKind.audio, mediaId: 19),
      throwsA(isA<ApiError>()),
    );
    await expectLater(
      repo.sendMedia(
        '42',
        kind: ChatMessageKind.audio,
        mediaId: 19,
        durationMs: 0,
      ),
      throwsA(isA<ApiError>()),
    );
    await expectLater(
      repo.sendMedia(
        '42',
        kind: ChatMessageKind.image,
        mediaId: 19,
        durationMs: 1,
      ),
      throwsA(isA<ApiError>()),
    );
    await expectLater(
      repo.sendMedia(
        '42',
        kind: ChatMessageKind.video,
        mediaId: 19,
        caption: 'not allowed',
      ),
      throwsA(isA<ApiError>()),
    );
    expect(api.requests, isEmpty);
  });
  test(
    'message pagination and both resync cursors use documented fields',
    () async {
      final page = await repo.messages('42', continuation: '2');
      expect(page.items.single.id, '101');
      expect(page.continuation, '2');
      expect(api.requests.last.queryParameters, {'page': 2});
      await repo.messageChanges('42', afterId: '101');
      expect(api.requests.last.queryParameters, {'after_id': 101});
      final date = DateTime.utc(2026, 11, 7);
      await repo.messageChanges('42', updatedSince: date);
      expect(api.requests.last.queryParameters, {
        'updated_since': date.toIso8601String(),
      });
      await expectLater(
        repo.messageChanges('42', afterId: '1', updatedSince: date),
        throwsArgumentError,
      );
    },
  );
  test(
    'delete message uses sender-authorized endpoint and confirmation',
    () async {
      await repo.deleteMessage('101');
      expect(api.requests.single.path, 'messages/101');
      expect(api.requests.single.method, 'DELETE');
    },
  );
  for (final type in ['text', 'image', 'voice', 'video']) {
    test('MessageResource $type parses verified enum', () {
      final message = ChatMessage.fromJson(messageJson(type: type));
      expect(message.kind, switch (type) {
        'text' => ChatMessageKind.text,
        'image' => ChatMessageKind.image,
        'voice' => ChatMessageKind.audio,
        _ => ChatMessageKind.video,
      });
    });
  }
  test('receipts are derived only from authoritative timestamps', () {
    expect(ChatMessage.fromJson(messageJson()).delivery, ChatDelivery.sent);
    expect(
      ChatMessage.fromJson(
        messageJson(delivered: '2026-11-07T12:02:00Z'),
      ).delivery,
      ChatDelivery.delivered,
    );
    expect(
      ChatMessage.fromJson(messageJson(read: '2026-11-07T12:03:00Z')).delivery,
      ChatDelivery.seen,
    );
  });
  test('deleted placeholder strips content and private attachment URL', () {
    final json = messageJson(type: 'image', deleted: true)
      ..['body'] = 'stale content'
      ..['media'] = [
        {'url': 'https://example.invalid/private'},
      ];
    final message = ChatMessage.fromJson(json);
    expect(message.isDeleted, true);
    expect(message.text, '');
    expect(message.mediaUrl, isNull);
  });
  test('reply resource retains quote/deleted state', () {
    final json = messageJson()
      ..['reply_to'] = {
        'id': 100,
        'sender_id': 7,
        'type': 'text',
        'body': null,
        'is_deleted': true,
      };
    final message = ChatMessage.fromJson(json);
    expect(message.replyTo!.id, '100');
    expect(message.replyTo!.isDeleted, true);
  });
  test(
    'broadcast auth is form-encoded and does not expose its signature',
    () async {
      final result = await repo.authorizeChannel(
        socketId: '1234.5678',
        channelName: 'presence-conversations.42',
      );
      expect(
        api.requests.single.contentType,
        Headers.formUrlEncodedContentType,
      );
      expect(api.wireBodies.single, contains('socket_id=1234.5678'));
      expect(result.toString(), isNot(contains('fixture-signature')));
    },
  );
  test('invalid channel/socket authentication is refused locally', () async {
    await expectLater(
      repo.authorizeChannel(socketId: 'bad', channelName: 'private-users.5'),
      throwsArgumentError,
    );
    expect(api.requests, isEmpty);
  });
  test(
    'pending inbox initiator may send; pending request recipient cannot',
    () async {
      final inbox = await repo.conversations();
      final requests = await repo.conversations(requests: true);
      expect(inbox.items.single.canSend, true);
      expect(requests.items.single.canSend, false);
    },
  );
  test('blocked thread never gains send permission', () async {
    final json = conversationJson()..['is_blocked'] = true;
    api.response = conversationPage(items: [json]);
    expect((await repo.conversations()).items.single.canSend, false);
  });
  for (final status in [401, 403, 404, 422, 429, 500, 503]) {
    test('HTTP $status is sanitized without changing auth session', () async {
      api.status = status;
      api.response = {'message': 'PRIVATE message text'};
      await expectLater(
        repo.sendText('42', 'PRIVATE draft'),
        throwsA(
          isA<ApiError>()
              .having((e) => e.statusCode, 'status', status)
              .having(
                (e) => e.message.contains('PRIVATE'),
                'private text not exposed',
                false,
              ),
        ),
      );
      expect(prefs.hasSession, true);
    });
  }
  test(
    'old-account send response cannot be used by a replacement session',
    () async {
      api.pending = Completer();
      final send = repo.sendText('42', 'Private');
      await Future<void>.delayed(Duration.zero);
      await prefs.saveToken('replacement');
      api.pending!.complete();
      await expectLater(send, throwsA(isA<ApiError>()));
    },
  );
}
