import 'package:flutter/material.dart';
import '../data/chat_media_selection.dart';
import '../data/chat_models.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'chat_image_upload_overlay.dart';

class ChatPendingMediaBubble extends StatelessWidget {
  const ChatPendingMediaBubble({
    super.key,
    required this.media,
    required this.sending,
    required this.onRetry,
    this.progress,
  });
  final ChatMediaSelection media;
  final bool sending;
  final double? progress;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerEnd,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .75,
        ),
        child: GestureDetector(
          onTap: sending ? null : onRetry,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (media.kind == ChatMessageKind.image)
                ChatImageUploadOverlay(
                  sending: sending,
                  progress: progress,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: Image.memory(
                      media.bytes,
                      width: 220,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const SizedBox(
                        width: 220,
                        height: 120,
                        child: Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white54,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else ...[
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF9B3900),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Icon(
                        media.kind == ChatMessageKind.audio
                            ? Icons.mic
                            : Icons.videocam,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                if (sending) ...[
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 120,
                    child: LinearProgressIndicator(
                      value: progress,
                      color: DarkColors.primaryColor,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                  const Text(
                    'Sending…',
                    style: TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ],
              ],
              if (!sending)
                TextButton(
                  onPressed: onRetry,
                  child: const Text(
                    'Failed to send. Tap to retry.',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
