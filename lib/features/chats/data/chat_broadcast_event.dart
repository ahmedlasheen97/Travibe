import 'dart:convert';
import 'chat_models.dart';
import 'chat_resource_parsers.dart';

/// Exact Reverb/Pusher event payloads from OpenAPI info.description. This parser
/// supplies no connection defaults and never trusts arbitrary route strings.
sealed class ChatBroadcastEvent {
  const ChatBroadcastEvent();
  String? get key;
  static ChatBroadcastEvent? parse(String name, Object? payload) {
    if (!{'message.sent', 'typing.updated', 'messages.read'}.contains(name)) {
      return null;
    }
    try {
      return _parseKnown(name, payload);
    } on FormatException {
      throw const FormatException('Unable to read chat broadcast event.');
    }
  }

  static ChatBroadcastEvent? _parseKnown(String name, Object? payload) {
    final json = chatObject(payload is String ? jsonDecode(payload) : payload);
    if (json == null) throw const FormatException('Invalid chat event.');
    return switch (name) {
      'message.sent' => ChatMessageSent(ChatMessage.fromJson(json)),
      'typing.updated' => ChatTypingUpdated(
        chatId(json['conversation_id']),
        chatId(json['user_id']),
        json['is_typing'] is bool
            ? json['is_typing'] as bool
            : throw const FormatException('Invalid typing event.'),
      ),
      'messages.read' => ChatMessagesRead(
        chatId(json['conversation_id']),
        chatId(json['reader_id']),
        chatId(json['last_read_message_id']),
        chatDate(json['read_at']) ??
            (throw const FormatException('Invalid read event.')),
      ),
      _ => null,
    };
  }

  @override
  String toString() => 'ChatBroadcastEvent(redacted)';
}

class ChatMessageSent extends ChatBroadcastEvent {
  const ChatMessageSent(this.message);
  final ChatMessage message;
  @override
  String get key => 'message.sent:${message.id}';
}

class ChatTypingUpdated extends ChatBroadcastEvent {
  const ChatTypingUpdated(this.conversationId, this.userId, this.isTyping);
  final String conversationId, userId;
  final bool isTyping;
  // Repeated true events renew ephemeral state; never deduplicate by value.
  @override
  String? get key => null;
}

class ChatMessagesRead extends ChatBroadcastEvent {
  const ChatMessagesRead(
    this.conversationId,
    this.readerId,
    this.lastReadMessageId,
    this.readAt,
  );
  final String conversationId, readerId, lastReadMessageId;
  final DateTime readAt;
  @override
  String get key =>
      'messages.read:$conversationId:$readerId:$lastReadMessageId:${readAt.toUtc().toIso8601String()}';

  /// Ignore own read echoes, other threads, incoming messages and IDs beyond the
  /// authoritative cursor. Never infer Seen from a route or HTTP send success.
  List<ChatMessage> apply(
    List<ChatMessage> messages, {
    required String currentUserId,
  }) => messages
      .map((message) {
        final id = int.tryParse(message.id),
            cursor = int.tryParse(lastReadMessageId);
        if (currentUserId.isEmpty ||
            readerId == currentUserId ||
            message.senderId != currentUserId ||
            message.conversationId != conversationId ||
            message.isDeleted ||
            id == null ||
            cursor == null ||
            id > cursor ||
            (message.readAt != null && !readAt.isAfter(message.readAt!))) {
          return message;
        }
        return ChatMessage(
          id: message.id,
          senderId: message.senderId,
          conversationId: message.conversationId,
          kind: message.kind,
          text: message.text,
          createdAt: message.createdAt,
          updatedAt: message.updatedAt,
          mediaUrl: message.mediaUrl,
          thumbnailUrl: message.thumbnailUrl,
          mediaId: message.mediaId,
          mediaWidth: message.mediaWidth,
          mediaHeight: message.mediaHeight,
          duration: message.duration,
          replyTo: message.replyTo,
          postId: message.postId,
          sharedPost: message.sharedPost,
          delivery: ChatDelivery.seen,
          readAt: readAt,
          deliveredAt: message.deliveredAt ?? readAt,
        );
      })
      .toList(growable: false);
}
