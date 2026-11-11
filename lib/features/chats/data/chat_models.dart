import 'chat_resource_parsers.dart';

/// Conversation resources supplied by the backend contract. Message endpoints
/// have their own contract; a last-message snapshot does not enable sending.
class ChatParticipant {
  const ChatParticipant({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.online,
    this.username,
    this.countryCode,
    this.onlineStatus,
    this.lastSeenAt,
    this.isFollowing,
    this.followsYou,
    this.isBlocked,
    this.followersCount,
    this.followingCount,
  });
  final String id, name;
  final String? avatarUrl;
  final bool? online;
  final String? username, countryCode, onlineStatus;
  final DateTime? lastSeenAt;
  final bool? isFollowing, followsYou, isBlocked;
  final int? followersCount, followingCount;

  factory ChatParticipant.fromJson(Map<String, dynamic> json) =>
      ChatParticipant(
        id: json['id'] == null ? '' : chatId(json['id']),
        name: chatString(json['name']) ?? 'Unavailable user',
        username: chatString(json['username']),
        countryCode: chatString(json['country_code']),
        avatarUrl: chatString(json['avatar_url']),
        // The schema describes a string but does not specify its enum values.
        // Keep it opaque; do not infer online/offline from non-empty strings.
        onlineStatus: json['is_online'] is String
            ? json['is_online'] as String
            : null,
        lastSeenAt: chatDate(json['last_seen_at']),
        isFollowing: chatBool(json['is_following']),
        followsYou: chatBool(json['follows_you']),
        isBlocked: chatBool(json['is_blocked']),
        followersCount: chatCount(json['followers_count']),
        followingCount: chatCount(json['following_count']),
      );
}

class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.participant,
    this.preview = '',
    this.updatedAt,
    this.unread = 0,
    this.hasUnreadCount = true,
    this.canSend = false,
    this.lastMessage,
    this.lastMessageAt,
    this.isMuted,
    this.isBlocked,
    this.acceptedAt,
    this.isAccepted,
    this.lastReadMessageId,
    this.createdAt,
  });
  final String id;
  final ChatParticipant participant;
  final String preview;
  final DateTime? updatedAt;
  final int unread;
  final bool hasUnreadCount;

  /// Must be supplied by a verified permission/request-state adapter.
  final bool canSend;
  final ChatLastMessage? lastMessage;
  final DateTime? lastMessageAt, acceptedAt, createdAt;
  final bool? isMuted, isBlocked, isAccepted;
  final String? lastReadMessageId;

  ChatConversation withSending(bool allowed) => ChatConversation(
    id: id,
    participant: participant,
    preview: preview,
    updatedAt: updatedAt,
    unread: unread,
    hasUnreadCount: hasUnreadCount,
    canSend: allowed,
    lastMessage: lastMessage,
    lastMessageAt: lastMessageAt,
    isMuted: isMuted,
    isBlocked: isBlocked,
    acceptedAt: acceptedAt,
    isAccepted: isAccepted,
    lastReadMessageId: lastReadMessageId,
    createdAt: createdAt,
  );

  ChatConversation withUnread(int value) => ChatConversation(
    id: id,
    participant: participant,
    preview: preview,
    updatedAt: updatedAt,
    unread: value,
    hasUnreadCount: hasUnreadCount,
    canSend: canSend,
    lastMessage: lastMessage,
    lastMessageAt: lastMessageAt,
    isMuted: isMuted,
    isBlocked: isBlocked,
    acceptedAt: acceptedAt,
    isAccepted: isAccepted,
    lastReadMessageId: lastReadMessageId,
    createdAt: createdAt,
  );

  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    final other = chatObject(json['other_user']);
    final snapshot = chatObject(json['last_message']);
    final last = snapshot == null ? null : ChatLastMessage.fromJson(snapshot);
    return ChatConversation(
      id: chatId(json['id']),
      participant: other == null
          ? const ChatParticipant(id: '', name: 'Unavailable user')
          : ChatParticipant.fromJson(other),
      lastMessage: last,
      preview: last?.isDeleted == true
          ? ''
          : last?.type == 'post'
          ? 'Shared a post'
          : last?.body ??
                switch (last?.type) {
                  'image' => 'Photo',
                  'voice' => 'Voice message',
                  'video' => 'Video',
                  _ => '',
                },
      unread: chatCount(json['unread_count']) ?? 0,
      hasUnreadCount:
          json['unread_count'] is int && (json['unread_count'] as int) >= 0,
      lastMessageAt: chatDate(json['last_message_at']),
      updatedAt: chatDate(json['updated_at']),
      createdAt: chatDate(json['created_at']),
      isMuted: chatBool(json['is_muted']),
      isBlocked: chatBool(json['is_blocked']),
      acceptedAt: chatDate(json['accepted_at']),
      isAccepted: chatBool(json['is_accepted']),
      lastReadMessageId: json['last_read_message_id'] == null
          ? null
          : chatId(json['last_read_message_id']),
      canSend:
          chatBool(json['is_accepted']) == true &&
          chatBool(json['is_blocked']) == false,
    );
  }
}

/// Preserve nested media/poster/reply structures without guessing their schema,
/// URL keys, message enum values or per-recipient receipt semantics.
class ChatLastMessage {
  ChatLastMessage.fromJson(Map<String, dynamic> json)
    : id = json['id'] == null ? null : chatId(json['id']),
      conversationId = json['conversation_id'] == null
          ? null
          : chatId(json['conversation_id']),
      senderId = json['sender_id'] == null ? null : chatId(json['sender_id']),
      type = chatString(json['type']),
      body = chatString(json['body']),
      media = freezeChatJson(json['media']),
      poster = freezeChatJson(json['poster']),
      replyTo = freezeChatJson(json['reply_to']),
      durationMs = chatCount(json['duration_ms']),
      postId = json['post_id'] == null ? null : chatId(json['post_id']),
      sharedPost = ChatSharedPost.tryParse(json['post']),
      isDeleted = chatBool(json['is_deleted']),
      deliveredAt = chatDate(json['delivered_at']),
      readAt = chatDate(json['read_at']),
      createdAt = chatDate(json['created_at']),
      updatedAt = chatDate(json['updated_at']),
      deletedAt = chatDate(json['deleted_at']);
  final String? id, conversationId, senderId, type, body;
  final Object? media, poster, replyTo;
  final int? durationMs;

  /// Shared post ID for `post` messages; kept when [sharedPost] is null.
  final String? postId;
  final ChatSharedPost? sharedPost;
  final bool? isDeleted;
  final DateTime? deliveredAt, readAt, createdAt, updatedAt, deletedAt;
}

/// Compact post card embedded in `post` messages (`SharedPostResource`).
/// Null on a message when the post was removed or the viewer may no longer
/// open it; the message keeps its `post_id`.
class ChatSharedPost {
  const ChatSharedPost({
    required this.id,
    required this.author,
    this.content,
    this.imageUrl,
    this.url,
    this.createdAt,
  });
  final String id;
  final ChatParticipant author;
  final String? content;
  final Uri? imageUrl, url;
  final DateTime? createdAt;

  /// Returns null for a missing card; throws for a malformed one.
  static ChatSharedPost? tryParse(Object? value) {
    final json = chatObject(value);
    if (json == null) return null;
    final user = chatObject(json['user']);
    final media = json['media'];
    final first = media is List && media.isNotEmpty
        ? chatObject(media.first)
        : null;
    return ChatSharedPost(
      id: chatId(json['id']),
      author: user == null
          ? const ChatParticipant(id: '', name: 'Travibe member')
          : ChatParticipant.fromJson(user),
      content: chatString(json['content']),
      imageUrl:
          chatHttpsUri(first?['thumbnail_url']) ?? chatHttpsUri(first?['url']),
      url: chatHttpsUri(json['url']),
      createdAt: chatDate(json['created_at']),
    );
  }
}

enum ChatMessageKind { text, image, audio, video, post, unsupported }

enum ChatDelivery { sending, sent, delivered, seen, failed }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.kind,
    this.text = '',
    this.createdAt,
    this.mediaUrl,
    this.thumbnailUrl,
    this.mediaId,
    this.mediaWidth,
    this.mediaHeight,
    this.duration,
    this.delivery = ChatDelivery.sent,
    this.conversationId,
    this.updatedAt,
    this.deletedAt,
    this.deliveredAt,
    this.readAt,
    this.isDeleted = false,
    this.replyTo,
    this.postId,
    this.sharedPost,
  });
  final String id, senderId, text;
  final ChatMessageKind kind;
  final DateTime? createdAt;
  final Uri? mediaUrl, thumbnailUrl;
  final String? mediaId;
  final int? mediaWidth, mediaHeight;
  final Duration? duration;
  final ChatDelivery delivery;
  final String? conversationId;
  final DateTime? updatedAt, deletedAt, deliveredAt, readAt;
  final bool isDeleted;
  final ChatLastMessage? replyTo;

  /// Shared post ID for [ChatMessageKind.post]; kept when [sharedPost] is
  /// null so the bubble can show "Post unavailable".
  final String? postId;
  final ChatSharedPost? sharedPost;
  ChatMessage asDeleted() => ChatMessage(
    id: id,
    senderId: senderId,
    kind: kind,
    conversationId: conversationId,
    createdAt: createdAt,
    isDeleted: true,
    delivery: delivery,
  );

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    if (json['is_deleted'] == null || json['type'] is! String) {
      throw const FormatException('Invalid message resource.');
    }
    final deleted = chatBool(json['is_deleted']) == true;
    final read = chatDate(json['read_at']),
        delivered = chatDate(json['delivered_at']);
    final media = json['media'];
    if (!deleted && media is! List) {
      throw const FormatException('Invalid message media.');
    }
    Uri? url;
    if (!deleted && media is List && media.isNotEmpty) {
      final resource = chatObject(media.first);
      final raw = chatString(resource?['url']);
      final candidate = raw == null ? null : Uri.tryParse(raw);
      if (candidate != null &&
          candidate.scheme == 'https' &&
          candidate.host.isNotEmpty &&
          candidate.userInfo.isEmpty) {
        url = candidate;
      }
    }
    Uri? preview(Object? value) {
      final raw = value is String ? Uri.tryParse(value) : null;
      return raw != null &&
              raw.scheme == 'https' &&
              raw.host.isNotEmpty &&
              raw.userInfo.isEmpty
          ? raw
          : null;
    }

    final thumbnail = !deleted && media is List && media.isNotEmpty
        ? preview(chatObject(media.first)?['thumbnail_url'])
        : null;
    final firstMedia = !deleted && media is List && media.isNotEmpty
        ? chatObject(media.first)
        : null;
    int? dimension(String key) {
      final value = firstMedia?[key];
      return value is int && value > 0 ? value : null;
    }

    final poster = chatObject(json['poster']);
    final reply = chatObject(json['reply_to']);
    return ChatMessage(
      id: chatId(json['id']),
      senderId: chatId(json['sender_id']),
      conversationId: chatId(json['conversation_id']),
      kind: switch (json['type']) {
        'text' => ChatMessageKind.text,
        'image' => ChatMessageKind.image,
        'voice' => ChatMessageKind.audio,
        'video' => ChatMessageKind.video,
        'post' => ChatMessageKind.post,
        _ => ChatMessageKind.unsupported,
      },
      postId: deleted || json['post_id'] == null
          ? null
          : chatId(json['post_id']),
      sharedPost: deleted ? null : ChatSharedPost.tryParse(json['post']),
      text: deleted ? '' : chatString(json['body']) ?? '',
      createdAt: chatDate(json['created_at']),
      updatedAt: chatDate(json['updated_at']),
      deletedAt: chatDate(json['deleted_at']),
      isDeleted: deleted,
      mediaUrl: url,
      mediaWidth: dimension('width'),
      mediaHeight: dimension('height'),
      thumbnailUrl:
          thumbnail ??
          preview(poster?['thumbnail_url']) ??
          preview(poster?['url']),
      mediaId:
          !deleted &&
              media is List &&
              media.isNotEmpty &&
              chatObject(media.first)?['id'] != null
          ? chatId(chatObject(media.first)!['id'])
          : null,
      duration: chatCount(json['duration_ms']) == null
          ? null
          : Duration(milliseconds: chatCount(json['duration_ms'])!),
      replyTo: reply == null || reply.isEmpty
          ? null
          : ChatLastMessage.fromJson(reply),
      readAt: read,
      deliveredAt: delivered,
      delivery: read != null
          ? ChatDelivery.seen
          : delivered != null
          ? ChatDelivery.delivered
          : ChatDelivery.sent,
    );
  }
}

/// Continuation is opaque: the adapter determines cursor vs page semantics.
class ChatPage<T> {
  ChatPage(Iterable<T> items, {this.continuation, this.total})
    : items = List.unmodifiable(items);
  final List<T> items;
  final String? continuation;
  final int? total;
}

class ChatCapabilities {
  const ChatCapabilities({
    this.list = false,
    this.messages = false,
    this.create = false,
    this.sendText = false,
    this.requests = false,
    this.requestActions = false,
    this.read = false,
    this.remove = false,
    this.detail = false,
    this.attachments = false,
  });
  final bool list,
      messages,
      create,
      sendText,
      requests,
      requestActions,
      read,
      remove,
      detail,
      attachments;
}

/// Authoritative receipts are monotonic. A late REST snapshot must not downgrade
/// a read event, resurrect a tombstone, or overwrite a newer server revision.
ChatMessage reconcileChatMessage(ChatMessage existing, ChatMessage incoming) {
  if (existing.id != incoming.id) return incoming;
  final oldTime = existing.updatedAt, newTime = incoming.updatedAt;
  final selected =
      existing.isDeleted && !incoming.isDeleted ||
          !incoming.isDeleted &&
              oldTime != null &&
              (newTime == null || oldTime.isAfter(newTime))
      ? existing
      : incoming;
  DateTime? latest(DateTime? a, DateTime? b) => a == null
      ? b
      : b == null || a.isAfter(b)
      ? a
      : b;
  final read = latest(existing.readAt, incoming.readAt);
  final delivered = latest(
    latest(existing.deliveredAt, incoming.deliveredAt),
    read,
  );
  return ChatMessage(
    id: selected.id,
    senderId: selected.senderId,
    kind: selected.kind,
    text: selected.text,
    createdAt: selected.createdAt,
    mediaUrl: selected.mediaUrl,
    thumbnailUrl: selected.thumbnailUrl,
    mediaId: selected.mediaId,
    mediaWidth: selected.mediaWidth,
    mediaHeight: selected.mediaHeight,
    duration: selected.duration,
    conversationId: selected.conversationId,
    updatedAt: selected.updatedAt,
    deletedAt: selected.deletedAt,
    isDeleted: selected.isDeleted,
    replyTo: selected.replyTo,
    postId: selected.postId,
    sharedPost: selected.sharedPost,
    deliveredAt: delivered,
    readAt: read,
    delivery: read != null
        ? ChatDelivery.seen
        : delivered != null
        ? ChatDelivery.delivered
        : selected.delivery,
  );
}
