import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import '../data/chat_models.dart';
import '../data/chat_resource_parsers.dart';
import 'chat_history_image.dart';

/// What a reply bar or quoted box shows about the original message.
class ChatReplyPreview {
  const ChatReplyPreview({
    required this.id,
    required this.senderId,
    required this.text,
    this.thumbnailUrl,
    this.deleted = false,
  });

  factory ChatReplyPreview.fromMessage(ChatMessage message) => ChatReplyPreview(
    id: message.id,
    senderId: message.senderId,
    deleted: message.isDeleted,
    text: chatReplyText(
      kind: message.kind,
      body: message.text,
      duration: message.duration,
      storyReply: message.isStoryReply,
    ),
    thumbnailUrl: message.isDeleted
        ? null
        : switch (message.kind) {
            ChatMessageKind.image => message.thumbnailUrl ?? message.mediaUrl,
            ChatMessageKind.video => message.thumbnailUrl,
            ChatMessageKind.post => message.sharedPost?.imageUrl,
            _ => null,
          },
  );

  /// From a bubble's `reply_to` snapshot. [original] is the loaded message,
  /// when available, for fresher media URLs.
  factory ChatReplyPreview.fromSnapshot(
    ChatLastMessage snapshot, {
    ChatMessage? original,
  }) {
    if (original != null && !original.isDeleted) {
      return ChatReplyPreview.fromMessage(original);
    }
    final kind = switch (snapshot.type) {
      'text' => ChatMessageKind.text,
      'image' => ChatMessageKind.image,
      'voice' => ChatMessageKind.audio,
      'video' => ChatMessageKind.video,
      'post' => ChatMessageKind.post,
      _ => ChatMessageKind.unsupported,
    };
    final media = snapshot.media;
    final first = media is List && media.isNotEmpty
        ? chatObject(media.first)
        : null;
    final poster = chatObject(snapshot.poster);
    return ChatReplyPreview(
      id: snapshot.id ?? '',
      senderId: snapshot.senderId ?? '',
      deleted: snapshot.isDeleted == true,
      text: chatReplyText(
        kind: kind,
        body: snapshot.body ?? '',
        duration: snapshot.durationMs == null
            ? null
            : Duration(milliseconds: snapshot.durationMs!),
        storyReply: snapshot.storyExpiresAt != null,
      ),
      thumbnailUrl: switch (kind) {
        ChatMessageKind.image =>
          chatHttpsUri(first?['thumbnail_url']) ?? chatHttpsUri(first?['url']),
        ChatMessageKind.video =>
          chatHttpsUri(first?['thumbnail_url']) ??
              chatHttpsUri(poster?['thumbnail_url']) ??
              chatHttpsUri(poster?['url']),
        ChatMessageKind.post => snapshot.sharedPost?.imageUrl,
        _ => null,
      },
    );
  }

  final String id, senderId, text;
  final Uri? thumbnailUrl;
  final bool deleted;
}

/// One-line preview: the text, or a label for media and shared posts.
String chatReplyText({
  required ChatMessageKind kind,
  required String body,
  Duration? duration,
  bool storyReply = false,
}) {
  final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  final label = switch (kind) {
    ChatMessageKind.image => text.isEmpty ? '📷 Photo' : '📷 $text',
    ChatMessageKind.video => '🎥 Video',
    ChatMessageKind.audio =>
      duration == null || duration <= Duration.zero
          ? '🎤 Voice note'
          : '🎤 Voice note · ${_clock(duration)}',
    ChatMessageKind.post => 'Shared a post',
    ChatMessageKind.text => text,
    ChatMessageKind.unsupported => text.isEmpty ? 'Message' : text,
  };
  if (!storyReply) return label;
  return label.isEmpty ? 'Story reply' : 'Story reply · $label';
}

String _clock(Duration value) {
  final seconds = (value.inMilliseconds / 1000).round();
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// Left line, name, one-line preview and an optional thumbnail. Used by the
/// composer's reply bar and inside reply bubbles.
class ChatReplyQuote extends StatelessWidget {
  const ChatReplyQuote({
    super.key,
    required this.title,
    required this.preview,
    required this.lineColor,
    this.background,
    this.onTap,
    this.titleColor = Colors.white,
    this.absorbTaps = false,
  });

  /// Swallows taps when [onTap] is null, so a dead quote (deleted original)
  /// doesn't fall through to the bubble's own tap.
  final bool absorbTaps;

  final String title;
  final ChatReplyPreview preview;
  final Color lineColor, titleColor;
  final Color? background;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final thumbnail = preview.deleted ? null : preview.thumbnailUrl;
    final content = Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: lineColor),
            Flexible(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preview.deleted ? 'Message deleted' : preview.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontStyle: preview.deleted
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (thumbnail != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  end: 6,
                  top: 4,
                  bottom: 4,
                ),
                child: IgnorePointer(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox.square(
                      dimension: 36,
                      child: ChatHistoryImage(
                        key: ValueKey(thumbnail),
                        url: thumbnail,
                        width: 36,
                        maxHeight: 36,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (onTap == null) {
      return absorbTaps
          ? GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: () {},
              child: content,
            )
          : content;
    }
    return Semantics(
      button: true,
      label: 'Show original message',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: content,
      ),
    );
  }
}

/// Orange line used by the composer bar and incoming quotes.
const chatReplyAccent = DarkColors.primaryColor;
