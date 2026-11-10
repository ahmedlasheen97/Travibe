import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/data/laravel_conversation_contract.dart';

class ChatE2eFailure implements Exception {
  const ChatE2eFailure(this.stage, [this.status]);
  final String stage;
  final int? status;
  @override
  String toString() => 'ChatE2eFailure(stage=$stage, http=$status)';
}

/// Test-only opt-in. Accounts/tokens must be supplied by the operator after
/// explicit permission. Never uses or extracts the app's restored session.
class ChatE2ePermit {
  ChatE2ePermit({
    required this.accountA,
    required this.accountB,
    this.writes = false,
    this.decline = false,
    this.channelAuthorization = false,
  }) {
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(accountA) ||
        !RegExp(r'^[1-9][0-9]*$').hasMatch(accountB) ||
        accountA == accountB) {
      throw const ChatE2eFailure('distinct_test_accounts_required');
    }
  }
  final String accountA, accountB;
  final bool writes, decline, channelAuthorization;
  void check(String method, String path) {
    final metadataRead =
        method == 'GET' &&
        (path == 'user' ||
            path == 'conversations' ||
            path == 'conversations/requests' ||
            RegExp(r'^conversations/[1-9][0-9]*$').hasMatch(path));
    if (metadataRead) return;
    if (method == 'POST' &&
        path == 'broadcasting/auth' &&
        channelAuthorization) {
      return;
    }
    // GET messages also marks incoming messages delivered: it is not read-only.
    if (!writes) throw const ChatE2eFailure('write_permission_required');
    if (method == 'POST' && path == 'conversations') return;
    if (method == 'GET' &&
        RegExp(r'^conversations/[1-9][0-9]*/messages$').hasMatch(path)) {
      return;
    }
    if (method == 'POST' &&
        RegExp(
          r'^conversations/[1-9][0-9]*/(messages|read|accept)$',
        ).hasMatch(path)) {
      return;
    }
    if (method == 'POST' &&
        RegExp(r'^conversations/[1-9][0-9]*/decline$').hasMatch(path) &&
        decline) {
      return;
    }
    throw const ChatE2eFailure('operation_not_permitted');
  }

  @override
  String toString() => 'ChatE2ePermit(redacted)';
}

class ChatE2eCreated {
  const ChatE2eCreated(this.conversation, this.isNew);
  final ChatConversation conversation;
  final bool isNew;
}

/// External test driver HTTP adapter, not a second production repository or
/// login/session service. Uses existing typed contract parsing. Two clients are
/// intentionally isolated from the app's one-current-account PreferencesManager.
class ChatE2eHttpActor {
  ChatE2eHttpActor({
    required this.id,
    required String token,
    required this.permit,
    Dio? dio,
  }) : _dio =
           dio ?? Dio(BaseOptions(baseUrl: 'https://travibeapp.com/api/v1/')) {
    if (!{permit.accountA, permit.accountB}.contains(id) ||
        token.trim().isEmpty) {
      throw const ChatE2eFailure('test_credentials_required');
    }
    _dio.options.baseUrl = 'https://travibeapp.com/api/v1/';
    _dio.options.followRedirects = false;
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.sendTimeout = const Duration(seconds: 15);
    _dio.options.receiveTimeout = const Duration(seconds: 15);
    _dio.options.headers.addAll({
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    });
    // Defense in depth for every request, including accidental direct calls.
    _dio.interceptors.insert(
      0,
      InterceptorsWrapper(
        onRequest: (request, handler) {
          try {
            permit.check(request.method, request.path);
            handler.next(request);
          } catch (_) {
            handler.reject(
              DioException(
                requestOptions: request,
                type: DioExceptionType.cancel,
              ),
            );
          }
        },
      ),
    );
  }
  final String id;
  final ChatE2ePermit permit;
  final Dio _dio;
  static const _wire = LaravelConversationContract();
  final _ownedConversations = <String>{};
  bool _verified = false;
  bool _closed = false;
  int _sends = 0, _creates = 0;
  Future<Response<Object?>> _request(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    String? contentType,
  }) async {
    if (_closed) throw const ChatE2eFailure('actor_closed');
    permit.check(method, path);
    if (!_verified && path != 'user') {
      throw const ChatE2eFailure('verify_account_first');
    }
    try {
      final result = await _dio
          .request<Object?>(
            path,
            data: data,
            queryParameters: query,
            options: Options(method: method, contentType: contentType),
          )
          .timeout(const Duration(seconds: 20));
      final expected = method == 'GET'
          ? {200}
          : path == 'conversations'
          ? {200, 201}
          : path.endsWith('/messages')
          ? {201}
          : {200};
      if (!expected.contains(result.statusCode)) {
        throw ChatE2eFailure('unexpected_http_status', result.statusCode);
      }
      return result;
    } on ChatE2eFailure {
      rethrow;
    } on DioException catch (error) {
      throw ChatE2eFailure('http_request', error.response?.statusCode);
    } catch (_) {
      throw const ChatE2eFailure('request_or_timeout');
    }
  }

  T _decode<T>(String stage, T Function() parse) {
    try {
      return parse();
    } catch (_) {
      throw ChatE2eFailure(stage);
    }
  }

  Future<void> verify() async {
    final response = await _request('GET', 'user');
    final value = response.data;
    final data = value is Map ? value['data'] : null;
    if (response.statusCode != 200 ||
        data is! Map ||
        data['id'].toString() != id ||
        data['email_verified_at'] == null) {
      throw const ChatE2eFailure('account_identity_or_verified_email');
    }
    _verified = true;
  }

  String get other => id == permit.accountA ? permit.accountB : permit.accountA;
  void _bind(ChatConversation conversation) {
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(conversation.id) ||
        conversation.participant.id != other) {
      throw const ChatE2eFailure('unexpected_conversation_pair');
    }
    _ownedConversations.add(conversation.id);
  }

  void _requireOwned(String conversation) {
    if (!_ownedConversations.contains(conversation)) {
      throw const ChatE2eFailure('unverified_conversation');
    }
  }

  Future<ChatPage<ChatConversation>> inbox({
    bool requests = false,
    String? next,
  }) async {
    final response = await _request(
      'GET',
      requests ? 'conversations/requests' : 'conversations',
      query: _wire.pagination(next),
    );
    return _decode(
      'conversation_page',
      () => _wire.decodeConversations(response.data),
    );
  }

  Future<ChatE2eCreated> create() async {
    if (++_creates > 1) throw const ChatE2eFailure('create_budget_exceeded');
    final response = await _request(
      'POST',
      'conversations',
      data: _wire.creationBody(other),
    );
    if (![200, 201].contains(response.statusCode)) {
      throw ChatE2eFailure('create_status', response.statusCode);
    }
    final conversation = _decode(
      'create_resource',
      () => _wire.decodeConversation(response.data),
    );
    _bind(conversation);
    return ChatE2eCreated(conversation, response.statusCode == 201);
  }

  Future<ChatConversation> detail(String conversation) async {
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(conversation)) {
      throw const ChatE2eFailure('invalid_test_conversation');
    }
    final response = await _request('GET', 'conversations/$conversation');
    final value = _decode(
      'detail_resource',
      () => _wire.decodeConversation(response.data),
    );
    if (value.id != conversation) {
      throw const ChatE2eFailure('different_conversation');
    }
    _bind(value);
    return value;
  }

  Future<ChatMessage> send(String conversation, String marker) async {
    _requireOwned(conversation);
    if (++_sends > 3) throw const ChatE2eFailure('send_budget_exceeded');
    final response = await _request(
      'POST',
      'conversations/$conversation/messages',
      data: _wire.textBody(marker),
    );
    if (response.statusCode != 201) {
      throw ChatE2eFailure('send_status', response.statusCode);
    }
    final value = _decode(
      'send_resource',
      () => _wire.decodeMessage(response.data),
    );
    if (value.senderId != id ||
        value.conversationId != conversation ||
        value.text != marker) {
      throw const ChatE2eFailure('message_reconciliation');
    }
    return value;
  }

  Future<ChatPage<ChatMessage>> messages(
    String conversation, {
    DateTime? updatedSince,
    String? next,
  }) async {
    _requireOwned(conversation);
    final response = await _request(
      'GET',
      'conversations/$conversation/messages',
      query: {
        ..._wire.pagination(next),
        if (updatedSince != null)
          'updated_since': updatedSince.toUtc().toIso8601String(),
      },
    );
    return _decode('message_page', () => _wire.decodeMessages(response.data));
  }

  Future<ChatConversation> accept(String conversation) async {
    _requireOwned(conversation);
    final response = await _request(
      'POST',
      'conversations/$conversation/accept',
    );
    final value = _decode(
      'accept_resource',
      () => _wire.decodeConversation(response.data),
    );
    _bind(value);
    if (value.isAccepted != true) {
      throw const ChatE2eFailure('accept_not_confirmed');
    }
    return value;
  }

  Future<ChatConversation> read(String conversation) async {
    _requireOwned(conversation);
    final response = await _request('POST', 'conversations/$conversation/read');
    final value = _decode(
      'read_resource',
      () => _wire.decodeConversation(response.data),
    );
    _bind(value);
    if (value.unread != 0) throw const ChatE2eFailure('read_not_confirmed');
    return value;
  }

  Future<void> decline(
    String conversation, {
    required bool createdByThisRun,
  }) async {
    _requireOwned(conversation);
    if (!createdByThisRun) {
      throw const ChatE2eFailure('cannot_decline_preexisting_thread');
    }
    final response = await _request(
      'POST',
      'conversations/$conversation/decline',
    );
    if (response.statusCode != 200 ||
        response.data is! Map ||
        (response.data as Map)['message'] is! String) {
      throw const ChatE2eFailure('decline_not_confirmed');
    }
  }

  Future<Map<String, Object?>> authorize(String socket, String channel) async {
    final own = channel == 'private-users.$id';
    final conversation = channel.startsWith('presence-conversations.')
        ? channel.substring('presence-conversations.'.length)
        : null;
    if (!RegExp(r'^\d+\.\d+$').hasMatch(socket) ||
        (!own && !_ownedConversations.contains(conversation))) {
      throw const ChatE2eFailure('unverified_channel');
    }
    final response = await _request(
      'POST',
      'broadcasting/auth',
      contentType: Headers.formUrlEncodedContentType,
      data: {'socket_id': socket, 'channel_name': channel},
    );
    final data = response.data;
    if (response.statusCode != 200 ||
        data is! Map ||
        data['auth'] is! String ||
        (data['auth'] as String).isEmpty ||
        (conversation != null && data['channel_data'] is! String)) {
      throw const ChatE2eFailure('channel_authorization');
    }
    if (conversation != null) {
      final identity = _decode(
        'presence_authorization_identity',
        () => jsonDecode(data['channel_data'] as String),
      );
      if (identity is! Map || identity['user_id'].toString() != id) {
        throw const ChatE2eFailure('presence_authorization_identity');
      }
    }
    return {
      'auth': data['auth'],
      if (data['channel_data'] != null) 'channel_data': data['channel_data'],
    };
  }

  void close() {
    _closed = true;
    _verified = false;
    _ownedConversations.clear();
    _dio.options.headers.remove('Authorization');
    _dio.close(force: true);
  }

  @override
  String toString() => 'ChatE2eHttpActor(redacted)';
}
