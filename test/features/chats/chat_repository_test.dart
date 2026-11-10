import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/data/chat_repository.dart';
import 'chat_fakes.dart';
import 'conversation_fixtures.dart';

// Synthetic adapter tests the boundary, NOT a claimed Laravel JSON contract.
class _FixtureContract implements ChatWireContract {
  @override
  ChatCapabilities get capabilities => const ChatCapabilities(
    list: true,
    messages: true,
    create: true,
    sendText: true,
    requests: true,
    requestActions: true,
    read: true,
    remove: true,
  );
  @override
  Map<String, dynamic> pagination(String? continuation) =>
      continuation == null ? {} : {'fixture_continuation': continuation};
  @override
  Map<String, dynamic> creationBody(String id) => {'fixture_recipient': id};
  @override
  Map<String, dynamic> textBody(String text) => {'fixture_text': text};
  @override
  Object? readBody() => null;
  @override
  Object? requestActionBody({required bool accept}) => null;
  @override
  ChatConversation decodeConversation(Object? response) =>
      const ChatConversation(
        id: '123',
        participant: participant,
        isAccepted: true,
        isBlocked: false,
        canSend: true,
      );
  @override
  ChatPage<ChatConversation> decodeConversations(Object? response) {
    if (response is! Map || response['fixture_valid'] != true) {
      throw const FormatException('fixture invalid');
    }
    return ChatPage([conversation]);
  }

  @override
  ChatMessage decodeMessage(Object? response) => message;
  @override
  ChatPage<ChatMessage> decodeMessages(Object? response) => ChatPage([message]);
}

class _Adapter implements HttpClientAdapter {
  int status = 200;
  bool offline = false, malformed = false;
  Object? responseData;
  final requests = <RequestOptions>[];
  Completer<void>? wait;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (wait != null) await wait!.future;
    if (offline) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionTimeout,
      );
    }
    return ResponseBody.fromString(
      jsonEncode(responseData ?? (malformed ? {} : {'fixture_valid': true})),
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
  final preferences = PreferencesManager();
  late _Adapter adapter;
  late LaravelChatRepository repo;
  late Dio dio;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.saveToken('fixture-session');
    adapter = _Adapter();
    dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/api/v1/'))
      ..httpClientAdapter = adapter;
    repo = LaravelChatRepository(dio: dio, contract: _FixtureContract());
  });
  test(
    'default production adapter parses inbox and requests beyond empty pages',
    () async {
      adapter.responseData = conversationPage(last: 2, total: 20);
      repo = LaravelChatRepository(dio: dio);
      final inbox = await repo.conversations();
      final requests = await repo.conversations(
        requests: true,
        continuation: inbox.continuation,
      );
      expect(inbox.items.single.id, '42');
      expect(requests.total, 20);
      expect(adapter.requests.map((r) => r.path), [
        'conversations',
        'conversations/requests',
      ]);
      expect(adapter.requests.last.queryParameters, {'page': 2});
    },
  );
  test(
    'default creation posts user_id and parses returned conversation',
    () async {
      adapter.responseData = {'data': conversationJson()};
      repo = LaravelChatRepository(dio: dio);
      final item = await repo.create('7');
      expect(item.id, '42');
      expect(adapter.requests.single.data, {'user_id': 7});
      expect(adapter.requests.single.method, 'POST');
    },
  );
  test(
    'conversation detail uses existing authenticated request configuration',
    () async {
      adapter.responseData = {'data': conversationJson()};
      repo = LaravelChatRepository(dio: dio);
      final item = await repo.conversation('42');
      expect(item.id, '42');
      expect(adapter.requests.single.path, 'conversations/42');
      expect(
        adapter.requests.single.extra['sessionRevision'],
        preferences.sessionRevision,
      );
    },
  );
  test('mismatching detail identity is rejected', () async {
    adapter.responseData = {'data': conversationJson()};
    repo = LaravelChatRepository(dio: dio);
    await expectLater(repo.conversation('43'), throwsA(isA<ApiError>()));
  });
  test(
    'typed accept retains the authoritative resource and rejects pending or mismatched responses',
    () async {
      repo = LaravelChatRepository(dio: dio);
      adapter.responseData = {'data': conversationJson()};
      await expectLater(repo.acceptRequest('42'), throwsA(isA<ApiError>()));
      adapter.responseData = {
        'data': conversationJson()..['is_accepted'] = true,
      };
      await expectLater(repo.acceptRequest('43'), throwsA(isA<ApiError>()));
      final result = await repo.acceptRequest('42');
      expect(result.id, '42');
      expect(result.isAccepted, true);
      expect(result.canSend, true);
      expect(
        adapter.requests.every(
          (request) => request.method == 'POST' && request.data == null,
        ),
        true,
      );
    },
  );
  test(
    'documented default mutations use verified bodies and response envelopes',
    () async {
      repo = LaravelChatRepository(dio: dio);
      adapter.responseData = {'data': conversationJson()};
      await repo.markRead('42');
      adapter.responseData = {
        'data': conversationJson()..['is_accepted'] = true,
      };
      await repo.resolveRequest('42', accept: true);
      adapter.responseData = {'message': 'Confirmed'};
      await repo.resolveRequest('42', accept: false);
      await repo.remove('42');
      expect(adapter.requests.map((r) => r.path), [
        'conversations/42/read',
        'conversations/42/accept',
        'conversations/42/decline',
        'conversations/42',
      ]);
      expect(adapter.requests.every((r) => r.data == null), true);
    },
  );
  test(
    'unauthorized conversation list does not silently clear session',
    () async {
      adapter.status = 401;
      repo = LaravelChatRepository(dio: dio);
      await expectLater(
        repo.conversations(),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'status', 401)),
      );
      expect(preferences.hasSession, true);
    },
  );
  test('late creation response from old account is rejected', () async {
    adapter.responseData = {'data': conversationJson()};
    adapter.wait = Completer();
    repo = LaravelChatRepository(dio: dio);
    final pending = repo.create('7');
    await Future<void>.delayed(Duration.zero);
    await preferences.saveToken('replacement-session');
    adapter.wait!.complete();
    await expectLater(pending, throwsA(isA<ApiError>()));
  });
  test(
    'observed empty Laravel envelope is parsed without fabricated resources',
    () {
      const contract = ObservedEmptyConversationContract();
      final page = contract.decodeConversations({
        'data': [],
        'meta': {'current_page': 1, 'last_page': 1, 'per_page': 15, 'total': 0},
      });
      expect(page.items, isEmpty);
      expect(page.continuation, isNull);
      expect(contract.capabilities.requestActions, false);
      expect(contract.capabilities.sendText, false);
    },
  );
  test(
    'unobserved conversation resources fail explicitly instead of being dropped',
    () {
      const contract = ObservedEmptyConversationContract();
      expect(
        () => contract.decodeConversations({
          'data': [
            {'unknown_resource': true},
          ],
          'meta': {'total': 1},
        }),
        throwsA(isA<ChatUnavailable>()),
      );
    },
  );
  test('inconsistent empty envelope is not silently accepted', () {
    const contract = ObservedEmptyConversationContract();
    for (final value in [
      null,
      {},
      {
        'data': [],
        'meta': {'total': 4},
      },
    ]) {
      expect(
        () => contract.decodeConversations(value),
        throwsA(isA<ApiError>()),
      );
    }
  });
  test('uses confirmed paths and contract-supplied bodies only', () async {
    await repo.conversations();
    await repo.conversations(requests: true);
    await repo.messages('123');
    await repo.create('other');
    await repo.sendText('123', 'Hello');
    await repo.markRead('123');
    await repo.resolveRequest('123', accept: true);
    await repo.resolveRequest('123', accept: false);
    await repo.remove('123');
    expect(adapter.requests.map((r) => '${r.method} ${r.path}'), [
      'GET conversations',
      'GET conversations/requests',
      'GET conversations/123/messages',
      'POST conversations',
      'POST conversations/123/messages',
      'POST conversations/123/read',
      'POST conversations/123/accept',
      'POST conversations/123/decline',
      'DELETE conversations/123',
    ]);
    expect(adapter.requests[3].data, {'fixture_recipient': 'other'});
    expect(adapter.requests[4].data, {'fixture_text': 'Hello'});
    expect(
      adapter.requests.every(
        (r) => r.extra['sessionRevision'] == preferences.sessionRevision,
      ),
      true,
    );
  });
  test(
    'pagination is supplied by adapter without guessing cursor or page',
    () async {
      await repo.conversations(continuation: 'opaque');
      expect(adapter.requests.single.queryParameters, {
        'fixture_continuation': 'opaque',
      });
    },
  );
  test('path IDs are encoded', () async {
    await repo.messages('id/with?characters');
    expect(
      adapter.requests.single.path,
      'conversations/id%2Fwith%3Fcharacters/messages',
    );
  });
  for (final status in [401, 403, 404, 422, 429, 500, 503]) {
    test('HTTP $status is sanitized and preserves status', () async {
      adapter.status = status;
      await expectLater(
        repo.sendText('123', 'Private text'),
        throwsA(
          isA<ApiError>()
              .having((e) => e.statusCode, 'status', status)
              .having(
                (e) => e.message.contains('Private text'),
                'no message disclosure',
                false,
              ),
        ),
      );
    });
  }
  test('connection timeout yields retryable non-secret error', () async {
    adapter.offline = true;
    await expectLater(repo.conversations(), throwsA(isA<ApiError>()));
  });
  test('malformed data never becomes empty success', () async {
    adapter.malformed = true;
    await expectLater(repo.conversations(), throwsFormatException);
  });
  test('session changes invalidate late responses', () async {
    adapter.wait = Completer();
    final pending = repo.conversations();
    await Future<void>.delayed(Duration.zero);
    await preferences.saveToken('another-account');
    adapter.wait!.complete();
    await expectLater(pending, throwsA(isA<ApiError>()));
  });
  test('logged-out operations do not reach transport', () async {
    await preferences.clearSession();
    await expectLater(repo.conversations(), throwsA(isA<ApiError>()));
    expect(adapter.requests, isEmpty);
  });
  test('empty message is refused before transport', () async {
    await expectLater(repo.sendText('123', '  '), throwsA(isA<ApiError>()));
    expect(adapter.requests, isEmpty);
  });
  test('204 destructive action does not require response parsing', () async {
    adapter.status = 204;
    await repo.remove('123');
    expect(adapter.requests.single.method, 'DELETE');
  });
}
