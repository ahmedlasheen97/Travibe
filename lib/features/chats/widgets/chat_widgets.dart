import 'chat_history_image.dart';
import '../screens/chat_image_viewer.dart';
export 'chat_attachment_menu.dart';
import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'chat_loading.dart';
import 'chat_expandable_text.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/utils/formatters.dart';
import 'package:travibe/features/home/widgets/home_user_avatar.dart';
import '../data/chat_models.dart';
import '../cubit/chat_audio_controller.dart';
import 'chat_video_message.dart';
import 'chat_post_card.dart';
import 'package:travibe/features/shares/screens/open_shared_post.dart';

class ChatListTile extends StatelessWidget {
  const ChatListTile({
    super.key,
    required this.conversation,
    required this.onTap,
  });
  final ChatConversation conversation;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final item = conversation;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                HomeUserAvatar(
                  url: item.participant.avatarUrl,
                  size: AppSizes.adaptiveRadius(52),
                ),
                if (item.participant.online == true)
                  PositionedDirectional(
                    end: 0,
                    bottom: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: DarkColors.backgroundColor,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.participant.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: item.unread > 0 ? Colors.white : Colors.white60,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  timeAgo(item.lastMessageAt ?? item.updatedAt),
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                if (item.unread > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Semantics(
                      label: '${item.unread} unread messages',
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 20,
                        ),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: DarkColors.primaryColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          item.unread > 99 ? '99+' : '${item.unread}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ChatsLoadingSkeleton extends StatelessWidget {
  const ChatsLoadingSkeleton({super.key});
  @override
  Widget build(BuildContext context) => ChatSkeleton(
    label: 'Loading conversations',
    child: Column(
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Bone(width: 108, height: 7),
              Bone(width: 108, height: 7),
            ],
          ),
        ),
        for (var i = 0; i < 8; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Bone.circle(size: AppSizes.adaptiveRadius(52)),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Bone(width: 108, height: 10),
                      SizedBox(height: 16),
                      Bone(width: 108, height: 7),
                    ],
                  ),
                ),
                const Column(
                  children: [
                    Bone(width: 40, height: 7),
                    SizedBox(height: 12),
                    Bone(width: 28, height: 18),
                  ],
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class ChatVoiceMessage extends StatelessWidget {
  const ChatVoiceMessage({
    super.key,
    this.duration,
    this.progress = 0,
    this.playing = false,
    this.onToggle,
  });
  final Duration? duration;
  final double progress;
  final bool playing;
  final VoidCallback? onToggle;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    child: Row(
      children: [
        IconButton(
          tooltip: onToggle == null
              ? 'Voice playback unavailable'
              : playing
              ? 'Pause voice message'
              : 'Play voice message',
          onPressed: onToggle,
          style: IconButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(44),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: DarkColors.primaryColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
        Expanded(
          child: LinearProgressIndicator(
            value: progress.clamp(0, 1),
            backgroundColor: Colors.white24,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          duration == null
              ? 'Audio'
              : '${duration!.inMinutes}:${(duration!.inSeconds % 60).toString().padLeft(2, '0')}',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    ),
  );
}

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.outgoing,
    this.audio,
    this.deletedMessageIds = const {},
    this.detailsExpanded = false,
    this.onDetailsTap,
    this.onRetry,
    this.onOpenPost,
  });
  final ChatMessage message;

  /// Opens a shared post; defaults to [openSharedPost].
  final void Function(int postId)? onOpenPost;
  final bool outgoing;
  final ChatAudioController? audio;
  final Set<String> deletedMessageIds;
  final bool detailsExpanded;
  final VoidCallback? onDetailsTap, onRetry;
  @override
  Widget build(BuildContext context) => Align(
    alignment: outgoing
        ? AlignmentDirectional.centerEnd
        : AlignmentDirectional.centerStart,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .82,
        ),
        child: Column(
          crossAxisAlignment: outgoing
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: message.delivery == ChatDelivery.failed
                  ? onRetry
                  : onDetailsTap,
              child: Semantics(
                button: onDetailsTap != null || onRetry != null,
                label: message.delivery == ChatDelivery.failed
                    ? 'Retry failed message'
                    : detailsExpanded
                    ? 'Hide message details'
                    : 'Show message details',
                onTap: message.delivery == ChatDelivery.failed
                    ? onRetry
                    : onDetailsTap,
                child: Container(
                  padding:
                      message.kind == ChatMessageKind.image &&
                          !message.isDeleted
                      ? EdgeInsets.zero
                      : _isPostCard
                      ? EdgeInsets.all(AppSizes.adaptiveWidth(8))
                      : message.kind == ChatMessageKind.audio
                      ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
                      : const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                  decoration: BoxDecoration(
                    color:
                        message.kind == ChatMessageKind.image &&
                            !message.isDeleted
                        ? Colors.transparent
                        // Shared posts use the grey frame in both directions.
                        : outgoing && !_isPostCard
                        ? const Color(0xFF9B3900)
                        : const Color(0xFF2C2C2C),
                    borderRadius: message.kind == ChatMessageKind.audio
                        ? BorderRadius.circular(32)
                        : BorderRadiusDirectional.only(
                            topStart: outgoing ? _corner : Radius.zero,
                            topEnd: outgoing ? Radius.zero : _corner,
                            bottomStart: _corner,
                            bottomEnd: _corner,
                          ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.replyTo != null && !message.isDeleted)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            message.replyTo!.isDeleted == true ||
                                    deletedMessageIds.contains(
                                      message.replyTo!.id,
                                    )
                                ? 'Deleted message'
                                : message.replyTo!.type == 'post'
                                ? 'Shared a post'
                                : message.replyTo!.body ?? 'Attachment',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      if (message.isDeleted)
                        const Text(
                          'Message deleted',
                          style: TextStyle(color: Colors.white60),
                        )
                      else
                        switch (message.kind) {
                          ChatMessageKind.text => ChatExpandableText(
                            text: message.text,
                            messageId: message.id,
                          ),
                          ChatMessageKind.image => _image(context),
                          ChatMessageKind.audio =>
                            audio == null
                                ? ChatVoiceMessage(duration: message.duration)
                                : AnimatedBuilder(
                                    animation: audio!,
                                    builder: (_, _) => ChatVoiceMessage(
                                      duration: message.duration,
                                      playing:
                                          audio!.currentMessageId ==
                                              message.id &&
                                          audio!.playing,
                                      progress:
                                          audio!.currentMessageId ==
                                                  message.id &&
                                              audio!.duration.inMilliseconds > 0
                                          ? audio!.position.inMilliseconds /
                                                audio!.duration.inMilliseconds
                                          : 0,
                                      onToggle: message.mediaUrl == null
                                          ? null
                                          : () => audio!.toggle(message),
                                    ),
                                  ),
                          ChatMessageKind.video => ChatVideoMessage(
                            url: message.mediaUrl,
                            audio: audio,
                          ),
                          ChatMessageKind.post => ChatPostCard(
                            post: message.sharedPost,
                            onOpen: _postOpener(context),
                          ),
                          ChatMessageKind.unsupported => const Text(
                            'Unsupported message',
                            style: TextStyle(color: Colors.white60),
                          ),
                        },
                      if (message.kind == ChatMessageKind.image &&
                          message.text.isNotEmpty &&
                          !message.isDeleted)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            message.text,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (outgoing && message.delivery == ChatDelivery.sending)
              const ChatSendingLabel()
            else if (message.delivery == ChatDelivery.failed)
              TextButton(
                onPressed: onRetry,
                child: const Text(
                  'Failed to send. Tap to retry.',
                  style: TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
            if (detailsExpanded &&
                !message.isDeleted &&
                message.delivery != ChatDelivery.failed &&
                message.delivery != ChatDelivery.sending)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _details(context),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    ),
  );
  bool get _isPostCard =>
      message.kind == ChatMessageKind.post && !message.isDeleted;

  Radius get _corner => _isPostCard
      ? Radius.circular(AppSizes.adaptiveRadius(24))
      : const Radius.circular(16);

  VoidCallback? _postOpener(BuildContext context) {
    final id = int.tryParse(message.sharedPost?.id ?? message.postId ?? '');
    if (message.sharedPost == null || id == null || id < 1) return null;
    return () =>
        onOpenPost != null ? onOpenPost!(id) : openSharedPost(context, id);
  }

  Widget _image(BuildContext context) {
    final url = message.mediaUrl;
    if (url == null || url.scheme != 'https' || url.host.isEmpty) {
      return const Text(
        'Image unavailable',
        style: TextStyle(color: Colors.white60),
      );
    }
    return Semantics(
      label: 'Image message. Open preview',
      button: true,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => ChatImageViewer(url: url)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260, maxHeight: 360),
            child: ChatHistoryImage(
              key: ValueKey(url),
              url: url,
              aspectRatio:
                  message.mediaWidth != null && message.mediaHeight != null
                  ? message.mediaWidth! / message.mediaHeight!
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  String _details(BuildContext context) {
    final at = message.createdAt?.toLocal();
    final time = at == null
        ? ''
        : MaterialLocalizations.of(
            context,
          ).formatTimeOfDay(TimeOfDay.fromDateTime(at));
    if (!outgoing) return time;
    final status = message.delivery == ChatDelivery.sending
        ? 'Sending…'
        : message.delivery == ChatDelivery.failed
        ? 'Failed'
        : message.readAt != null
        ? 'Seen'
        : message.deliveredAt != null
        ? 'Delivered'
        : 'Sent';
    return time.isEmpty ? status : '$time · $status';
  }
}

/// Muted status shown under an outgoing message while it is being sent. It
/// occupies the same slot (a [TextButton]) as "Failed to send. Tap to retry."
/// so the bubble does not shift when a send fails.
class ChatSendingLabel extends StatelessWidget {
  const ChatSendingLabel({super.key, this.fontSize = 12});

  /// Matches the sibling failure text; null keeps the theme size.
  final double? fontSize;
  @override
  Widget build(BuildContext context) => TextButton(
    key: const ValueKey('chat-message-sending'),
    onPressed: null,
    child: Text(
      'Sending…',
      style: TextStyle(color: Colors.white54, fontSize: fontSize),
    ),
  );
}
