import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'chat_models.dart';
import 'chat_repository.dart';
import 'chat_resource_parsers.dart';

/// Verified against docs/chat-openapi.json downloaded from authorized docs.
class LaravelConversationContract implements ChatWireContract {
  const LaravelConversationContract();
  @override
  ChatCapabilities get capabilities => const ChatCapabilities(
    list: true,
    requests: true,
    create: true,
    detail: true,
    messages: true,
    sendText: true,
    requestActions: true,
    read: true,
    remove: true,
    attachments: true,
  );

  @override
  Map<String, dynamic> pagination(String? continuation) {
    if (continuation == null) return const {};
    final page = int.tryParse(continuation);
    if (page == null || page < 1) {
      throw ArgumentError('Invalid conversation page.');
    }
    return {'page': page};
  }

  @override
  ChatPage<ChatConversation> decodeConversations(Object? response) =>
      _decode(() {
        final envelope = chatObject(response);
        final data = envelope?['data'];
        final meta = chatObject(envelope?['meta']);
        if (data is! List || meta == null) throw const FormatException();
        final current = chatCount(meta['current_page']);
        final last = chatCount(meta['last_page']);
        final total = chatCount(meta['total']);
        if (current == null ||
            current < 1 ||
            last == null ||
            last < 1 ||
            total == null) {
          throw const FormatException();
        }
        final items = data.map((item) {
          final json = chatObject(item);
          if (json == null) throw const FormatException();
          return ChatConversation.fromJson(json);
        }).toList();
        return ChatPage(
          items,
          continuation: current < last ? '${current + 1}' : null,
          total: total,
        );
      });

  @override
  ChatConversation decodeConversation(Object? response) => _decode(() {
    final json = chatObject(chatObject(response)?['data']);
    if (json == null) throw const FormatException();
    return ChatConversation.fromJson(json);
  });

  T _decode<T>(T Function() parse) {
    try {
      return parse();
    } on FormatException {
      throw ApiError(
        message: 'Unable to read the conversation response. Please retry.',
      );
    }
  }

  @override
  Map<String, dynamic> creationBody(String participantId) {
    final id = chatId(participantId);
    final numeric = int.tryParse(id);
    if (numeric == null || numeric < 1) {
      throw const FormatException('Invalid participant identifier.');
    }
    return {'user_id': numeric};
  }

  @override
  ChatPage<ChatMessage> decodeMessages(Object? response) => _decode(() {
    final envelope = chatObject(response),
        meta = chatObject(chatObject(response)?['meta']);
    final data = envelope?['data'];
    if (data is! List || meta == null) throw const FormatException();
    final current = chatCount(meta['current_page']),
        last = chatCount(meta['last_page']),
        total = chatCount(meta['total']);
    if (current == null ||
        current < 1 ||
        last == null ||
        last < 1 ||
        total == null) {
      throw const FormatException();
    }
    final items = data
        .map(
          (item) => ChatMessage.fromJson(
            chatObject(item) ?? (throw const FormatException()),
          ),
        )
        .toList();
    return ChatPage(
      items,
      continuation: current < last ? '${current + 1}' : null,
      total: total,
    );
  });
  @override
  ChatMessage decodeMessage(Object? response) => _decode(
    () => ChatMessage.fromJson(
      chatObject(chatObject(response)?['data']) ??
          (throw const FormatException()),
    ),
  );
  @override
  Map<String, dynamic> textBody(String text) {
    if (text.trim().isEmpty || text.runes.length > 5000) {
      throw ApiError(
        message: 'Enter a message of up to 5000 characters.',
        statusCode: 422,
      );
    }
    return {'type': 'text', 'body': text};
  }

  @override
  Object? readBody() => null;
  @override
  Object? requestActionBody({required bool accept}) => null;
}
