import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import '../data/chat_media_selection.dart';
import '../data/chat_models.dart';
import 'chat_waveform.dart';
import 'chat_widgets.dart';

class ChatPendingMediaBubble extends StatelessWidget {
  const ChatPendingMediaBubble({
    super.key,
    required this.media,
    required this.sending,
    required this.onRetry,
    this.progress,
    this.onCancel,
    this.error,
    this.onDiscard,
  });
  final ChatMediaSelection media;
  final bool sending;
  final VoidCallback onRetry;

  /// Upload fraction (0–1); null spins indeterminately (processing/sending).
  final double? progress;

  /// Non-null while the upload can still be cancelled.
  final VoidCallback? onCancel;

  /// Failure text; the bubble's retry is the only retry control.
  final String? error;

  /// Drops a failed voice note.
  final VoidCallback? onDiscard;

  /// "Voice note · 0:12" — never the upload filename.
  static String voiceLabel(int? durationMs) => durationMs == null
      ? 'Voice note'
      : 'Voice note · ${formatVoiceClock(Duration(milliseconds: durationMs))}';

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
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ConstrainedBox(
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
                      if (sending) _ring(),
                    ],
                  ),
                )
              else if (media.kind == ChatMessageKind.audio)
                _voice()
              else
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF9B3900),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: sending
                          ? _ring()
                          : SizedBox.square(
                              dimension: 48,
                              child: const Icon(
                                Icons.videocam,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
              if (sending)
                const ChatSendingLabel(fontSize: null)
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: TextButton(
                        onPressed: onRetry,
                        child: Text(
                          error ?? 'Failed to send. Tap to retry.',
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    ),
                    if (onDiscard != null &&
                        media.kind == ChatMessageKind.audio)
                      IconButton(
                        tooltip: 'Discard voice note',
                        onPressed: onDiscard,
                        icon: const Icon(Icons.close, color: Colors.white60),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _voice() => Container(
    key: const ValueKey('chat-pending-voice'),
    padding: AppSizes.chatVoiceBubblePadding,
    decoration: BoxDecoration(
      color: const Color(0xFF9B3900),
      borderRadius: BorderRadius.circular(AppSizes.chatVoicePillRadius),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (sending)
          _ring()
        else
          SizedBox.square(
            dimension: AppSizes.chatVoiceTapTarget,
            child: Center(
              child: Container(
                width: AppSizes.chatVoiceButtonSize,
                height: AppSizes.chatVoiceButtonSize,
                decoration: const BoxDecoration(
                  color: DarkColors.primaryColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.mic_rounded,
                  color: Colors.white,
                  size: AppSizes.chatVoiceIconSize,
                ),
              ),
            ),
          ),
        SizedBox(width: AppSizes.chatVoiceGap / 2),
        Flexible(
          child: Text(
            voiceLabel(media.durationMs),
            style: TextStyle(
              color: Colors.white,
              fontSize: AppSizes.chatVoiceTimerFont,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _ring() => Container(
    key: const ValueKey('chat-upload-ring'),
    width: 48,
    height: 48,
    decoration: const BoxDecoration(
      color: Colors.black54,
      shape: BoxShape.circle,
    ),
    child: Stack(
      alignment: Alignment.center,
      children: [
        SizedBox.square(
          dimension: 44,
          child: CircularProgressIndicator(
            value: progress?.clamp(0.0, 1.0),
            strokeWidth: 3,
            backgroundColor: Colors.white24,
            semanticsLabel: 'Uploading attachment',
          ),
        ),
        if (onCancel != null)
          IconButton(
            tooltip: 'Cancel upload',
            onPressed: onCancel,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            icon: const Icon(Icons.close, color: Colors.white, size: 20),
          ),
      ],
    ),
  );
}
