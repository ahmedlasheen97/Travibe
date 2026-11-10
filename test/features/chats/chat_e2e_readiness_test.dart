import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/features/chats/data/reverb_readiness.dart';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/data/chat_broadcast_event.dart';
import '../../support/chat_e2e/reverb_test_peer.dart';
import '../../support/chat_e2e/chat_e2e_actor.dart';
import '../../support/chat_e2e/chat_e2e_scenario.dart';

class Backend implements HttpClientAdapter {
  final calls = <String>[];
  final messages = <Map<String, Object?>>[];
  final authorizedSockets = <String>[];
  bool publishEvents = true;
  bool accepted = false,
      read = false,
      removed = false,
      existing = false,
      unauthorized = false;
  Map<String, Object?> conversation(bool isA) => {
    'id': 42,
    'other_user': {'id': isA ? 22 : 11, 'name': 'Approved test peer'},
    'is_accepted': accepted,
    'is_blocked': false,
    'unread_count': !isA && !read ? messages.length : 0,
  };
  Map<String, Object?> page(List<Object?> data) => {
    'data': data,
    'meta': {'current_page': 1, 'last_page': 1, 'total': data.length},
  };
  @override
  Future<ResponseBody> fetch(
    RequestOptions request,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    calls.add('${request.method} ${request.path}');
    final isA = request.headers['Authorization'] == 'Bearer fixture-A';
    Object? response;
    var status = 200;
    final path = request.path;
    if (unauthorized) {
      status = 401;
      response = {'message': 'PRIVATE_TOKEN_OR_MESSAGE_MUST_NOT_LEAK'};
    } else if (path == 'user') {
      response = {
        'data': {
          'id': isA ? 11 : 22,
          'email_verified_at': '2026-11-08T00:00:00Z',
        },
      };
    } else if (path == 'conversations' && request.method == 'POST') {
      status = existing ? 200 : 201;
      response = {'data': conversation(isA)};
    } else if (path == 'conversations/42' && removed) {
      status = 404;
      response = {'message': 'Removed'};
    } else if (path == 'conversations/42') {
      response = {'data': conversation(isA)};
    } else if (path == 'conversations/requests') {
      response = page(accepted ? [] : [conversation(isA)]);
    } else if (path == 'conversations') {
      response = page([conversation(isA)]);
    } else if (path == 'conversations/42/accept') {
      accepted = true;
      response = {'data': conversation(isA)};
    } else if (path == 'conversations/42/decline') {
      removed = true;
      response = {'message': 'Declined'};
    } else if (path == 'conversations/42/read') {
      read = true;
      response = {'data': conversation(isA)};
    } else if (path == 'conversations/42/messages' &&
        request.method == 'POST') {
      status = 201;
      final message = <String, Object?>{
        'id': 101 + messages.length,
        'conversation_id': 42,
        'sender_id': isA ? 11 : 22,
        'type': 'text',
        'body': (request.data as Map)['body'],
        'media': [],
        'is_deleted': false,
        'created_at': '2026-11-08T10:00:00Z',
        'updated_at': '2026-11-08T10:00:00Z',
      };
      messages.add(message);
      response = {'data': message};
    } else if (path == 'conversations/42/messages') {
      response = page(
        messages
            .map(
              (m) => {
                ...m,
                'delivered_at': '2026-11-08T10:00:01Z',
                if (read) 'read_at': '2026-11-08T10:00:02Z',
              },
            )
            .toList(),
      );
    } else if (path == 'broadcasting/auth') {
      authorizedSockets.add((request.data as Map)['socket_id'] as String);
      response = {
        'auth': 'REDACTED_TEST_SIGNATURE',
        'channel_data': jsonEncode({'user_id': isA ? '11' : '22'}),
      };
    } else {
      status = 500;
      response = {'message': 'Unexpected operation'};
    }
    return ResponseBody.fromString(
      jsonEncode(response),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class FakePeer implements ChatE2ePeer {
  FakePeer(this.backend, this.socket);
  final Backend backend;
  final String socket;
  bool closed = false;
  final channels = <String>{};
  @override
  Future<void> subscribe(ChatE2eHttpActor actor, String channel) async {
    if (closed) throw const ChatE2eFailure('closed_fake_socket');
    await actor.authorize(socket, channel);
    channels.add(channel);
  }

  @override
  Future<ChatMessage> message(String id) async {
    if (closed ||
        !backend.publishEvents ||
        !channels.contains('presence-conversations.42')) {
      throw const ChatE2eFailure('message_event_delivery');
    }
    return ChatMessage.fromJson(
      backend.messages.singleWhere((m) => m['id'].toString() == id),
    );
  }

  @override
  Future<ChatMessagesRead> readReceipt(
    String conversation,
    String reader,
    String message,
  ) async {
    if (!backend.read || !backend.publishEvents) {
      throw const ChatE2eFailure('read_event_delivery');
    }
    return ChatMessagesRead(
      conversation,
      reader,
      message,
      DateTime.utc(2026, 11, 8, 10, 0, 2),
    );
  }

  @override
  Future<void> close() async {
    closed = true;
    channels.clear();
  }
}

void main() {
  final deployment = ReverbDeployment(
    base: Uri.parse('wss://travibeapp.com/reverb'),
    publicKey: 'public-test-key',
  );
  test(
    'WSS defaults to TLS port 443 and protocol URI includes only public configuration',
    () {
      expect(deployment.port, 443);
      expect(deployment.protocolUri.path, '/reverb/app/public-test-key');
      expect(deployment.protocolUri.queryParameters['protocol'], '7');
      expect(
        () => ReverbDeployment(
          base: Uri.parse('ws://travibeapp.com/reverb'),
          publicKey: 'key',
        ),
        throwsArgumentError,
      );
    },
  );
  test('connection requires exact acknowledged event and valid socket ID', () {
    final info = ReverbConnectionInfo.parse(
      jsonEncode({
        'event': 'pusher:connection_established',
        'data': jsonEncode({'socket_id': '1.2', 'activity_timeout': 30}),
      }),
    );
    expect(info.activityTimeout.inSeconds, 30);
    expect(info.toString(), isNot(contains('1.2')));
    for (final frame in [
      <String, Object?>{'event': 'other', 'data': {}},
      <String, Object?>{
        'event': 'pusher:connection_established',
        'data': {'socket_id': 'bad', 'activity_timeout': 30},
      },
    ]) {
      expect(() => ReverbConnectionInfo.parse(frame), throwsFormatException);
    }
  });
  test(
    'read-only permit blocks every server mutation and delivery-affecting GET',
    () {
      final permit = ChatE2ePermit(accountA: '11', accountB: '22');
      permit.check('GET', 'user');
      permit.check('GET', 'conversations');
      permit.check('GET', 'conversations/requests');
      for (final operation in [
        ('POST', 'conversations'),
        ('GET', 'conversations/42/messages'),
        ('POST', 'conversations/42/read'),
        ('POST', 'conversations/42/accept'),
        ('POST', 'conversations/42/decline'),
        ('POST', 'broadcasting/auth'),
        ('DELETE', 'conversations/42'),
      ]) {
        expect(
          () => permit.check(operation.$1, operation.$2),
          throwsA(isA<ChatE2eFailure>()),
        );
      }
      expect(
        () => ChatE2ePermit(accountA: '11', accountB: '11', writes: true),
        throwsA(isA<ChatE2eFailure>()),
      );
    },
  );
  ({ChatE2eHttpActor a, ChatE2eHttpActor b, Backend backend}) actors({
    bool writes = false,
    bool decline = false,
    bool auth = false,
  }) {
    final server = Backend();
    final permit = ChatE2ePermit(
      accountA: '11',
      accountB: '22',
      writes: writes,
      decline: decline,
      channelAuthorization: auth,
    );
    Dio client() => Dio()..httpClientAdapter = server;
    return (
      a: ChatE2eHttpActor(
        id: '11',
        token: 'fixture-A',
        permit: permit,
        dio: client(),
      ),
      b: ChatE2eHttpActor(
        id: '22',
        token: 'fixture-B',
        permit: permit,
        dio: client(),
      ),
      backend: server,
    );
  }

  test('unapproved scenario fails before any network call', () async {
    final pair = actors();
    await expectLater(
      runChatE2e(a: pair.a, b: pair.b, deployment: deployment),
      throwsA(isA<ChatE2eFailure>()),
    );
    expect(pair.backend.calls, isEmpty);
    pair.a.close();
    pair.b.close();
  });
  test(
    'verified principals are required before creation and cross-account resources are rejected',
    () async {
      final pair = actors(writes: true);
      await expectLater(pair.a.create(), throwsA(isA<ChatE2eFailure>()));
      expect(pair.backend.calls, isEmpty);
      // A deliberately wrong credential identity cannot become an approved actor.
      final mismatch = ChatE2eHttpActor(
        id: '11',
        token: 'fixture-B',
        permit: pair.a.permit,
        dio: Dio()..httpClientAdapter = pair.backend,
      );
      await expectLater(mismatch.verify(), throwsA(isA<ChatE2eFailure>()));
      mismatch.close();
      pair.a.close();
      pair.b.close();
    },
  );
  test(
    'mocked two-account request acceptance send receive read and list refresh complete',
    () async {
      final pair = actors(writes: true);
      final result = await runChatE2e(
        a: pair.a,
        b: pair.b,
        deployment: deployment,
      );
      expect(result.stages['request_accepted'], true);
      expect(result.stages['rest_receive'], true);
      expect(result.stages['server_read_timestamp'], true);
      expect(result.stages.containsKey('message_event_delivery'), false);
      expect(pair.backend.messages.length, 2);
      expect(pair.backend.calls, contains('POST conversations/42/read'));
      expect(pair.backend.calls.any((s) => s.startsWith('DELETE')), false);
      pair.a.close();
      pair.b.close();
    },
  );
  test(
    'decline is separate, explicitly enabled and only for a fresh pending test thread',
    () async {
      final pair = actors(writes: true, decline: true);
      final result = await runChatE2e(
        a: pair.a,
        b: pair.b,
        deployment: deployment,
        decline: true,
      );
      expect(result.stages['request_declined'], true);
      expect(pair.backend.messages.length, 1);
      expect(pair.backend.removed, true);
      pair.a.close();
      pair.b.close();
    },
  );
  test('preexisting conversation stops before sending or declining', () async {
    final pair = actors(writes: true, decline: true);
    pair.backend.existing = true;
    await expectLater(
      runChatE2e(a: pair.a, b: pair.b, deployment: deployment, decline: true),
      throwsA(isA<ChatE2eFailure>()),
    );
    expect(pair.backend.messages, isEmpty);
    expect(pair.backend.removed, false);
    pair.a.close();
    pair.b.close();
  });
  test(
    'auth and subscription are not conflated; actor cannot sign another user channel',
    () async {
      final pair = actors(auth: true);
      await pair.a.verify();
      await expectLater(
        pair.a.authorize('1.2', 'private-users.22'),
        throwsA(isA<ChatE2eFailure>()),
      );
      await expectLater(
        pair.a.authorize('1.2', 'presence-conversations.42'),
        throwsA(isA<ChatE2eFailure>()),
      );
      final signed = await pair.a.authorize('1.2', 'private-users.11');
      expect(signed['auth'], isNotEmpty);
      // No WebSocket subscription/event-delivery result exists from an HTTP signature.
      expect(
        pair.backend.calls.where((s) => s == 'POST broadcasting/auth'),
        hasLength(1),
      );
      pair.a.close();
      pair.b.close();
    },
  );
  test(
    'HTTP errors never include response bodies bearer tokens or request data',
    () async {
      final pair = actors();
      pair.backend.unauthorized = true;
      try {
        await pair.a.verify();
        fail('Expected unauthorized');
      } on ChatE2eFailure catch (error) {
        expect(error.status, 401);
        expect(error.toString(), isNot(contains('PRIVATE')));
        expect(error.toString(), isNot(contains('fixture-A')));
      }
      pair.a.close();
      pair.b.close();
    },
  );
  test(
    'signature alone cannot pass subscription acknowledgement validation',
    () {
      expect(
        reverbSubscriptionAcknowledged({
          'auth': 'signature',
        }, channel: 'private-users.11'),
        false,
      );
      expect(
        reverbSubscriptionAcknowledged({
          'event': 'pusher_internal:subscription_succeeded',
          'channel': 'private-users.22',
          'data': '{}',
        }, channel: 'private-users.11'),
        false,
      );
      expect(
        reverbSubscriptionAcknowledged({
          'event': 'pusher_internal:subscription_succeeded',
          'channel': 'private-users.11',
          'data': '{}',
        }, channel: 'private-users.11'),
        true,
      );
      expect(
        reverbSubscriptionAcknowledged({
          'event': 'pusher_internal:subscription_succeeded',
          'channel': 'presence-conversations.42',
          'data': '{}',
        }, channel: 'presence-conversations.42'),
        false,
      );
      expect(
        reverbSubscriptionAcknowledged({
          'event': 'pusher_internal:subscription_succeeded',
          'channel': 'presence-conversations.42',
          'data': jsonEncode({
            'presence': {
              'ids': ['11'],
              'hash': {'11': {}},
              'count': 1,
            },
          }),
        }, channel: 'presence-conversations.42'),
        true,
      );
    },
  );
  test('malformed connection frame never exposes frame contents', () {
    try {
      ReverbConnectionInfo.parse('PRIVATE_FRAME_CONTENT');
      fail('Expected malformed');
    } on FormatException catch (error) {
      expect(error.toString(), isNot(contains('PRIVATE_FRAME_CONTENT')));
    }
  });
  test(
    'mocked event delivery read receipt and reconnect REST reconciliation are separate stages',
    () async {
      final pair = actors(writes: true, auth: true);
      final peers = <FakePeer>[];
      final result = await runChatE2e(
        a: pair.a,
        b: pair.b,
        deployment: deployment,
        realtime: true,
        peerFactory: () async {
          final peer = FakePeer(pair.backend, '${peers.length + 1}.2');
          peers.add(peer);
          return peer;
        },
      );
      expect(result.stages['message_event_delivery'], true);
      expect(result.stages['read_event_delivery'], true);
      expect(result.stages['reconnect_rest_reconciliation'], true);
      expect(peers, hasLength(3));
      expect(peers.every((peer) => peer.closed), true);
      expect(pair.backend.authorizedSockets.toSet(), {'1.2', '2.2', '3.2'});
      expect(pair.backend.messages, hasLength(3));
      pair.a.close();
      pair.b.close();
    },
  );
  test(
    'successful HTTP send and subscription never substitute for a missing message event',
    () async {
      final pair = actors(writes: true, auth: true);
      pair.backend.publishEvents = false;
      var socket = 0;
      await expectLater(
        runChatE2e(
          a: pair.a,
          b: pair.b,
          deployment: deployment,
          realtime: true,
          peerFactory: () async => FakePeer(pair.backend, '${++socket}.2'),
        ),
        throwsA(
          isA<ChatE2eFailure>().having(
            (error) => error.stage,
            'stage',
            'message_event_delivery',
          ),
        ),
      );
      expect(pair.backend.messages, isNotEmpty);
      pair.a.close();
      pair.b.close();
    },
  );
  test(
    'decline without separate approval fails before network activity',
    () async {
      final pair = actors(writes: true);
      await expectLater(
        runChatE2e(a: pair.a, b: pair.b, deployment: deployment, decline: true),
        throwsA(isA<ChatE2eFailure>()),
      );
      expect(pair.backend.calls, isEmpty);
      pair.a.close();
      pair.b.close();
    },
  );
}
