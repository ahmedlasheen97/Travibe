import 'dart:io';

import 'package:dio/dio.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/dio_client.dart';
import 'chat_models.dart';
import 'chat_reachability.dart';
import 'laravel_conversation_contract.dart';

class ChatUnavailable extends ApiError {
  ChatUnavailable()
    : super(message: 'Messaging is not available yet. Please try again later.');
}

/// A transport rejection before request transmission is safe to retry directly.
class ChatPreSendFailure extends ApiError {
  ChatPreSendFailure()
    : super(message: 'Unable to connect. Check your connection and try again.');
}

/// A successful create acknowledgement with an incomplete resource may still
/// provide a correlation ID. It is not shown as Sent until REST resolves it.
class ChatUnconfirmedSend extends ApiError {
  ChatUnconfirmedSend({this.serverMessageId})
    : super(message: 'Delivery is not yet confirmed.');
  final String? serverMessageId;
}

abstract interface class ChatRepository {
  ChatCapabilities get capabilities;
  Future<ChatPage<ChatConversation>> conversations({
    String? continuation,
    bool requests = false,
  });
  Future<ChatPage<ChatMessage>> messages(String id, {String? continuation});
  Future<ChatConversation> create(String participantId);
  Future<ChatMessage> sendText(String id, String text);
  Future<void> markRead(String id);
  Future<void> resolveRequest(String id, {required bool accept});
  Future<void> remove(String id);
  void cancel();
}

abstract interface class ConversationSearchRepository {
  Future<ChatPage<ChatConversation>> searchConversations(
    String search, {
    String? continuation,
    bool requests = false,
  });
}

abstract interface class ConversationDetailsRepository {
  Future<ChatConversation> conversation(String id);
}

abstract interface class ConversationRequestRepository {
  Future<ChatConversation> acceptRequest(String id);
  Future<void> declineRequest(String id);
}

abstract interface class ChatOperationsRepository
    implements ConversationDetailsRepository {
  Future<ChatConversation> setMuted(String id, bool muted);
  Future<ChatConversation> readConversation(String id);
  Future<void> typing(String id, bool typing);
  Future<ChatMessage> reply(String id, String text, String replyToId);

  /// Shares a post (`type: post`). 422 when the post is not visible to both
  /// participants or is blocked from either.
  Future<ChatMessage> sendPost(String id, int postId);
  Future<ChatMessage> sendMedia(
    String id, {
    required ChatMessageKind kind,
    required int mediaId,
    String? caption,
    int? durationMs,
    int? posterMediaId,
    String? replyToId,
  });
  Future<void> deleteMessage(String messageId);
  Future<ChatPage<ChatMessage>> messageChanges(
    String id, {
    String? afterId,
    DateTime? updatedSince,
    String? continuation,
  });
}

/// Wire schema seam. Implement only after receiving the Laravel resource,
/// validation and pagination schemas. These names are internal, not JSON keys.
abstract interface class ChatWireContract {
  ChatCapabilities get capabilities;
  Map<String, dynamic> pagination(String? continuation);
  ChatPage<ChatConversation> decodeConversations(Object? response);
  ChatPage<ChatMessage> decodeMessages(Object? response);
  ChatConversation decodeConversation(Object? response);
  ChatMessage decodeMessage(Object? response);
  Map<String, dynamic> creationBody(String participantId);
  Map<String, dynamic> textBody(String text);
  Object? readBody();
  Object? requestActionBody({required bool accept});
}

/// Existing Dio interceptor supplies credentials, guarded by the captured
/// sessionRevision. Never stores tokens or logs request/response contents.
class LaravelChatRepository
    implements
        ChatRepository,
        ChatOperationsRepository,
        ConversationRequestRepository,
        ConversationSearchRepository {
  LaravelChatRepository({
    Dio? dio,
    this.contract = const LaravelConversationContract(),
    PreferencesManager? preferences,
    ChatReachability? reachability,
  }) : _dio = dio ?? DioClient().dio,
       _preferences = preferences ?? PreferencesManager(),
       _reachability = reachability ?? ChatReachability.instance;
  final Dio _dio;
  final ChatReachability _reachability;
  final PreferencesManager _preferences;
  final ChatWireContract? contract;
  CancelToken _cancel = CancelToken();
  @override
  ChatCapabilities get capabilities =>
      contract?.capabilities ?? const ChatCapabilities();
  ChatWireContract _require(bool enabled) {
    if (!enabled || contract == null) throw ChatUnavailable();
    return contract!;
  }

  String _id(String id) {
    if (id.trim().isEmpty) throw ArgumentError('Missing conversation ID');
    return Uri.encodeComponent(id);
  }

  Future<Object?> _request(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    String? contentType,
  }) async {
    if (!_preferences.hasSession) {
      throw ApiError(message: 'Sign in to use messaging.');
    }
    final revision = _preferences.sessionRevision;
    final cancellation = _cancel;
    try {
      final response = await _dio
          .request<Object?>(
            path,
            data: body,
            queryParameters: query,
            cancelToken: cancellation,
            options: Options(
              method: method,
              contentType: contentType,
              sendTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 20),
              extra: {'sessionRevision': revision},
            ),
          )
          .timeout(
            const Duration(seconds: 25),
            onTimeout: () {
              cancellation.cancel();
              throw ApiError(message: 'Messaging timed out. Please retry.');
            },
          );
      _reachability.markReachable();
      if (revision != _preferences.sessionRevision) {
        throw ApiError(message: 'The account session changed.');
      }
      if (contract is LaravelConversationContract) {
        final expected = method == 'POST' && path == 'conversations'
            ? {200, 201}
            : method == 'POST' && path.endsWith('/messages')
            ? {201}
            : {200};
        if (!expected.contains(response.statusCode)) {
          throw ApiError(
            message:
                'The server did not confirm this operation. Refresh before retrying.',
          );
        }
      }
      return response.data;
    } on DioException catch (error) {
      // Dio raises connectionError with a SocketException only while opening
      // the connection, before any request bytes are sent.
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.badCertificate ||
          error.type == DioExceptionType.connectionError &&
              error.error is SocketException) {
        throw ChatPreSendFailure();
      }
      if (error.response != null) _reachability.markReachable();
      // Fixed user-facing messages. Validation bodies may contain private text.
      final status = error.response?.statusCode;
      throw ApiError(
        statusCode: status,
        message: switch (status) {
          401 => 'Sign in again to use messaging.',
          403 => 'Messaging is not permitted for this account or conversation.',
          404 => 'This conversation is no longer available.',
          422 => 'The message or request was not accepted.',
          429 => 'Too many requests. Please wait before trying again.',
          _ =>
            error.type == DioExceptionType.cancel
                ? 'The account session changed.'
                : 'Unable to connect to messaging. Please retry.',
        },
      );
    } on ApiError {
      rethrow;
    } catch (_) {
      throw ApiError(
        message: 'Unable to read the messaging response. Please retry.',
      );
    }
  }

  @override
  Future<ChatPage<ChatConversation>> conversations({
    String? continuation,
    bool requests = false,
  }) => searchConversations('', continuation: continuation, requests: requests);

  @override
  Future<ChatPage<ChatConversation>> searchConversations(
    String search, {
    String? continuation,
    bool requests = false,
  }) async {
    if (search.length > 100) throw ArgumentError('Search is too long.');
    final wire = _require(requests ? capabilities.requests : capabilities.list);
    final page = wire.decodeConversations(
      await _request(
        'GET',
        requests ? 'conversations/requests' : 'conversations',
        query: {
          ...wire.pagination(continuation),
          if (search.trim().isNotEmpty) 'search': search.trim(),
        },
      ),
    );
    if (wire is! LaravelConversationContract) return page;
    // Inbox includes pending threads started by this viewer; requests do not.
    return ChatPage(
      page.items.map(
        (item) => item.withSending(
          item.isBlocked == false && (!requests || item.isAccepted == true),
        ),
      ),
      continuation: page.continuation,
      total: page.total,
    );
  }

  @override
  Future<ChatPage<ChatMessage>> messages(
    String id, {
    String? continuation,
  }) async {
    final wire = _require(capabilities.messages);
    return wire.decodeMessages(
      await _request(
        'GET',
        'conversations/${_id(id)}/messages',
        query: wire.pagination(continuation),
      ),
    );
  }

  @override
  Future<ChatConversation> create(String participantId) async {
    final wire = _require(capabilities.create);
    final result = wire.decodeConversation(
      await _request(
        'POST',
        'conversations',
        body: wire.creationBody(participantId),
      ),
    );
    return wire is LaravelConversationContract
        ? result.withSending(result.isBlocked == false)
        : result;
  }

  @override
  Future<ChatConversation> conversation(String id) async {
    final wire = _require(capabilities.detail);
    final result = wire.decodeConversation(
      await _request('GET', 'conversations/${_id(id)}'),
    );
    if (result.id != id) {
      throw ApiError(
        message: 'Unable to read this conversation. Please retry.',
      );
    }
    return result;
  }

  @override
  Future<ChatMessage> sendText(String id, String text) async {
    if (text.trim().isEmpty) throw ApiError(message: 'Enter a message.');
    final wire = _require(capabilities.sendText);
    return _decodeSent(
      wire,
      id,
      await _request(
        'POST',
        'conversations/${_id(id)}/messages',
        body: wire.textBody(text),
      ),
    );
  }

  ChatMessage _decodeSent(
    ChatWireContract wire,
    String conversationId,
    Object? response,
  ) {
    try {
      return wire.decodeMessage(response);
    } catch (_) {
      final data = response is Map ? response['data'] : null;
      final id = data is Map ? data['id'] : null;
      final thread = data is Map ? data['conversation_id'] : null;
      throw ChatUnconfirmedSend(
        serverMessageId:
            id is int && id > 0 && thread?.toString() == conversationId
            ? '$id'
            : null,
      );
    }
  }

  @override
  Future<void> markRead(String id) async {
    final wire = _require(capabilities.read);
    final response = await _request(
      'POST',
      'conversations/${_id(id)}/read',
      body: wire.readBody(),
    );
    if (wire is LaravelConversationContract) wire.decodeConversation(response);
  }

  @override
  Future<void> resolveRequest(String id, {required bool accept}) async {
    if (accept) {
      await acceptRequest(id);
    } else {
      await declineRequest(id);
    }
  }

  @override
  Future<ChatConversation> acceptRequest(String id) async {
    final wire = _require(capabilities.requestActions);
    final response = await _request(
      'POST',
      'conversations/${_id(id)}/accept',
      body: wire.requestActionBody(accept: true),
    );
    final result = wire.decodeConversation(response);
    if (result.id != id || result.isAccepted != true) {
      throw ApiError(
        message: 'Acceptance was not confirmed. Refresh before retrying.',
      );
    }
    return result.withSending(result.isBlocked == false);
  }

  @override
  Future<void> declineRequest(String id) async {
    final wire = _require(capabilities.requestActions);
    final response = await _request(
      'POST',
      'conversations/${_id(id)}/decline',
      body: wire.requestActionBody(accept: false),
    );
    if (wire is LaravelConversationContract) _confirmation(response);
  }

  @override
  Future<void> remove(String id) async {
    _require(capabilities.remove);
    final response = await _request('DELETE', 'conversations/${_id(id)}');
    if (contract is LaravelConversationContract) _confirmation(response);
  }

  void _confirmation(Object? response) {
    if (response is! Map || response['message'] is! String) {
      throw ApiError(
        message:
            'The server did not confirm this change. Refresh before retrying.',
      );
    }
  }

  int _numeric(String id) {
    final value = int.tryParse(id);
    if (value == null || value < 1) {
      throw ApiError(message: 'Invalid messaging identifier.');
    }
    return value;
  }

  @override
  Future<ChatConversation> setMuted(String id, bool muted) async {
    final wire = _require(capabilities.detail);
    return wire.decodeConversation(
      await _request(
        'PATCH',
        'conversations/${_id(id)}',
        body: {'is_muted': muted},
      ),
    );
  }

  @override
  Future<ChatConversation> readConversation(String id) async {
    final wire = _require(capabilities.read);
    return wire.decodeConversation(
      await _request('POST', 'conversations/${_id(id)}/read'),
    );
  }

  @override
  Future<void> typing(String id, bool typing) async {
    _require(capabilities.sendText);
    _confirmation(
      await _request(
        'POST',
        'conversations/${_id(id)}/typing',
        body: {'is_typing': typing},
      ),
    );
  }

  @override
  Future<ChatMessage> reply(String id, String text, String replyToId) async {
    final wire = _require(capabilities.sendText);
    return _decodeSent(
      wire,
      id,
      await _request(
        'POST',
        'conversations/${_id(id)}/messages',
        body: {...wire.textBody(text), 'reply_to_id': _numeric(replyToId)},
      ),
    );
  }

  @override
  Future<ChatMessage> sendPost(String id, int postId) async {
    if (postId < 1) throw ApiError(message: 'This post cannot be shared.');
    final wire = _require(capabilities.sendText);
    return _decodeSent(
      wire,
      id,
      await _request(
        'POST',
        'conversations/${_id(id)}/messages',
        body: {'type': 'post', 'post_id': postId},
      ),
    );
  }

  @override
  Future<ChatMessage> sendMedia(
    String id, {
    required ChatMessageKind kind,
    required int mediaId,
    String? caption,
    int? durationMs,
    int? posterMediaId,
    String? replyToId,
  }) async {
    final wire = _require(capabilities.attachments);
    final type = switch (kind) {
      ChatMessageKind.image => 'image',
      ChatMessageKind.audio => 'voice',
      ChatMessageKind.video => 'video',
      _ => null,
    };
    if (type == null ||
        mediaId < 1 ||
        (kind != ChatMessageKind.image && caption != null) ||
        (caption != null && caption.runes.length > 1000) ||
        (durationMs != null && (durationMs < 1 || durationMs > 86400000)) ||
        (kind == ChatMessageKind.audio && durationMs == null) ||
        (kind == ChatMessageKind.image && durationMs != null) ||
        (posterMediaId != null && posterMediaId < 1) ||
        (kind != ChatMessageKind.video && posterMediaId != null)) {
      throw ApiError(
        message: 'The attachment is not valid for this message type.',
      );
    }
    return _decodeSent(
      wire,
      id,
      await _request(
        'POST',
        'conversations/${_id(id)}/messages',
        body: {
          'type': type,
          'media_id': mediaId,
          'body': ?caption,
          'duration_ms': ?durationMs,
          'poster_media_id': ?posterMediaId,
          if (replyToId != null) 'reply_to_id': _numeric(replyToId),
        },
      ),
    );
  }

  @override
  Future<void> deleteMessage(String messageId) async {
    _require(capabilities.messages);
    _confirmation(await _request('DELETE', 'messages/${_id(messageId)}'));
  }

  @override
  Future<ChatPage<ChatMessage>> messageChanges(
    String id, {
    String? afterId,
    DateTime? updatedSince,
    String? continuation,
  }) async {
    final wire = _require(capabilities.messages);
    if (afterId != null && updatedSince != null) {
      throw ArgumentError('Choose one message change cursor.');
    }
    return wire.decodeMessages(
      await _request(
        'GET',
        'conversations/${_id(id)}/messages',
        query: {
          ...wire.pagination(continuation),
          if (afterId != null) 'after_id': _numeric(afterId),
          if (updatedSince != null)
            'updated_since': updatedSince.toUtc().toIso8601String(),
        },
      ),
    );
  }

  /// Documented Pusher authorization only, not a WebSocket subscription.
  Future<ChatChannelAuthorization> authorizeChannel({
    required String socketId,
    required String channelName,
  }) async {
    if (!RegExp(r'^\d+\.\d+$').hasMatch(socketId) ||
        !RegExp(
          r'^(private-users|presence-conversations)\.[1-9][0-9]*$',
        ).hasMatch(channelName)) {
      throw ArgumentError('Invalid broadcasting channel authorization.');
    }
    final response = await _request(
      'POST',
      'broadcasting/auth',
      body: {'socket_id': socketId, 'channel_name': channelName},
      contentType: Headers.formUrlEncodedContentType,
    );
    if (response is! Map ||
        response['auth'] is! String ||
        (response['auth'] as String).isEmpty ||
        (response['channel_data'] != null &&
            response['channel_data'] is! String)) {
      throw ApiError(message: 'Unable to authorize the notification channel.');
    }
    return ChatChannelAuthorization(
      response['auth'] as String,
      response['channel_data'] as String?,
    );
  }

  @override
  void cancel() {
    _cancel.cancel();
    _cancel = CancelToken();
  }
}

class ChatChannelAuthorization {
  const ChatChannelAuthorization(this.auth, this.channelData);
  final String auth;
  final String? channelData;
  @override
  String toString() => 'ChatChannelAuthorization(redacted)';
}

/// Authenticated Simulator GETs on 2026-11-07 confirmed empty data arrays and
/// Laravel page metadata for both inbox endpoints. No non-empty resource or
/// mutation schema was observed. Do not turn unknown records into fake rows.
class ObservedEmptyConversationContract implements ChatWireContract {
  const ObservedEmptyConversationContract();
  @override
  ChatCapabilities get capabilities =>
      const ChatCapabilities(list: true, requests: true);
  @override
  Map<String, dynamic> pagination(String? continuation) {
    if (continuation != null) throw ChatUnavailable();
    return const {};
  }

  @override
  ChatPage<ChatConversation> decodeConversations(Object? response) {
    if (response is! Map ||
        response['data'] is! List ||
        response['meta'] is! Map) {
      throw ApiError(
        message: 'Unable to read the conversation response. Please retry.',
      );
    }
    final data = response['data'] as List;
    final meta = response['meta'] as Map;
    if (data.isNotEmpty) throw ChatUnavailable();
    if (meta['total'] != 0 ||
        meta['current_page'] != 1 ||
        meta['last_page'] != 1 ||
        meta['per_page'] is! int ||
        (meta['per_page'] as int) < 1) {
      throw ApiError(
        message: 'Unable to read the conversation response. Please retry.',
      );
    }
    return ChatPage(const <ChatConversation>[]);
  }

  @override
  ChatPage<ChatMessage> decodeMessages(Object? response) =>
      throw ChatUnavailable();
  @override
  ChatConversation decodeConversation(Object? response) =>
      throw ChatUnavailable();
  @override
  ChatMessage decodeMessage(Object? response) => throw ChatUnavailable();
  @override
  Map<String, dynamic> creationBody(String participantId) =>
      throw ChatUnavailable();
  @override
  Map<String, dynamic> textBody(String text) => throw ChatUnavailable();
  @override
  Object? readBody() => throw ChatUnavailable();
  @override
  Object? requestActionBody({required bool accept}) => throw ChatUnavailable();
}
