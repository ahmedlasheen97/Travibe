import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../data/chat_media_selection.dart';
import '../data/chat_models.dart';
import 'chat_send_button.dart';

class ChatSelectedMediaTray extends StatelessWidget {
  const ChatSelectedMediaTray({
    super.key,
    required this.items,
    required this.onRemove,
    required this.onSend,
    this.sending = false,
    this.progress,
    this.showSendButton = true,
    this.showUploadIndicator = true,
  });
  final List<ChatMediaSelection> items;
  final void Function(ChatMediaSelection) onRemove;
  final VoidCallback onSend;
  final bool sending;
  final bool showSendButton, showUploadIndicator;
  final double? progress;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height < 500 ? 48 : 86,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, index) {
                final item = items[index];
                return SizedBox(
                  width: 76,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: item.kind == ChatMessageKind.image
                              ? Image.memory(
                                  item.bytes,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const Icon(
                                    Icons.broken_image,
                                    color: Colors.white54,
                                  ),
                                )
                              : const ColoredBox(
                                  color: Color(0xFF292929),
                                  child: Icon(
                                    Icons.videocam,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: SizedBox.square(
                          dimension: 36,
                          child: IconButton(
                            tooltip: 'Remove selected attachment ${index + 1}',
                            padding: EdgeInsets.zero,
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black54,
                            ),
                            onPressed: sending ? null : () => onRemove(item),
                            icon: const Icon(
                              Icons.close,
                              size: 18,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      if (sending && showUploadIndicator && index == 0)
                        Positioned.fill(
                          child: ColoredBox(
                            color: Colors.black54,
                            child: Center(
                              child: CupertinoActivityIndicator(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        if (showSendButton) ...[
          const SizedBox(width: 8),
          ChatSendButton(
            tooltip: sending ? 'Sending attachments' : 'Send attachments',
            loading: sending,
            onPressed: sending ? null : onSend,
          ),
        ],
      ],
    ),
  );
}
