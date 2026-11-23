import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/glass_confirm_dialog.dart';
import 'package:travibe/core/widgets/glass_surface.dart';
import '../cubit/chat_audio_controller.dart';
import 'chat_send_button.dart';
import 'chat_waveform.dart';

/// Preview pill grey and the dark play circle (Figma voice preview).
const chatVoicePreviewColor = Color(0xFF4A4A4A);
const chatVoicePlayCircleColor = Color(0xFF1C1C1C);

/// Recordings at least this long ask before being discarded.
const chatVoiceConfirmDiscardAfter = Duration(seconds: 3);

/// Replaces the text-field row while recording (orange pill) or previewing
/// (grey pill); 🗑 and send sit underneath.
class ChatVoiceComposer extends StatelessWidget {
  const ChatVoiceComposer({
    super.key,
    required this.audio,
    required this.canSend,
    required this.uploading,
    required this.onSendVoice,
  });
  final ChatAudioController audio;
  final bool canSend, uploading;
  final VoidCallback onSendVoice;

  Future<void> _send() async {
    if (audio.recording) await audio.stopRecording();
    if (audio.draft != null) onSendVoice();
  }

  Future<void> _discard(BuildContext context) async {
    final length = audio.recording
        ? audio.recordingDuration
        : Duration(milliseconds: audio.draft?.durationMs ?? 0);
    if (length >= chatVoiceConfirmDiscardAfter) {
      final confirmed = await showGlassConfirmDialog(
        context,
        title: 'Discard voice note?',
        message: 'This recording will be deleted.',
        confirmLabel: 'Discard',
      );
      if (!confirmed) return;
    }
    if (audio.recording) {
      await audio.cancelRecording();
    } else {
      audio.discardDraft();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('chat-voice-composer'),
      mainAxisSize: MainAxisSize.min,
      children: [
        audio.recording ? _recordingPill() : _previewPill(),
        SizedBox(height: AppSizes.chatVoiceRowGap),
        Row(
          children: [
            Tooltip(
              message: 'Discard voice note',
              child: Semantics(
                button: true,
                label: 'Discard voice note',
                excludeSemantics: true,
                child: GestureDetector(
                  key: const ValueKey('chat-voice-discard'),
                  onTap: () => _discard(context),
                  child: SizedBox.square(
                    dimension: AppSizes.chatVoiceActionSize,
                    child: GlassSurface(
                      radius: AppSizes.chatVoiceActionSize / 2,
                      child: Center(
                        child: SvgPicture.asset(
                          'assets/images/icons/trash.svg',
                          width: AppSizes.chatVoiceActionIconSize,
                          height: AppSizes.chatVoiceActionIconSize,
                          colorFilter: const ColorFilter.mode(
                            Colors.white,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Spacer(),
            ChatSendButton(
              tooltip: 'Send voice note',
              onPressed: !canSend || uploading ? null : _send,
            ),
          ],
        ),
      ],
    );
  }

  Widget _pill({required Color color, required List<Widget> children}) =>
      Container(
        height: AppSizes.chatVoicePillHeight,
        padding: AppSizes.chatVoicePillPadding,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppSizes.chatVoicePillRadius),
        ),
        child: Row(children: children),
      );

  Widget _timer(Duration value) => Text(
    formatVoiceClock(value),
    style: TextStyle(
      color: Colors.white,
      fontSize: AppSizes.chatVoiceTimerFont,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );

  Widget _circle({
    required String tooltip,
    required Color color,
    required Widget child,
    required VoidCallback? onTap,
    Key? key,
  }) => Tooltip(
    message: tooltip,
    child: Semantics(
      button: true,
      label: tooltip,
      excludeSemantics: true,
      child: GestureDetector(
        key: key,
        onTap: onTap,
        child: Container(
          width: AppSizes.chatVoiceButtonSize,
          height: AppSizes.chatVoiceButtonSize,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    ),
  );

  Widget _recordingPill() => _pill(
    color: DarkColors.primaryColor,
    children: [
      _circle(
        key: const ValueKey('chat-voice-stop'),
        tooltip: 'Stop recording',
        color: Colors.white,
        onTap: audio.stopRecording,
        child: Container(
          width: AppSizes.chatVoiceStopSize,
          height: AppSizes.chatVoiceStopSize,
          decoration: BoxDecoration(
            color: DarkColors.primaryColor,
            borderRadius: BorderRadius.circular(AppSizes.chatVoiceStopSize / 4),
          ),
        ),
      ),
      SizedBox(width: AppSizes.chatVoiceGap),
      Expanded(
        child: Semantics(
          label: 'Live microphone level',
          child: ChatWaveform(samples: List.of(audio.levels), alignEnd: true),
        ),
      ),
      SizedBox(width: AppSizes.chatVoiceGap),
      _timer(audio.recordingDuration),
    ],
  );

  Widget _previewPill() {
    final draft = audio.draft;
    if (draft == null) return const SizedBox.shrink();
    final current = audio.currentMessageId == ChatAudioController.draftId;
    final playing = current && audio.playing;
    final total = Duration(milliseconds: draft.durationMs);
    final length = current && audio.duration > Duration.zero
        ? audio.duration
        : total;
    final progress = current && length.inMilliseconds > 0
        ? audio.position.inMilliseconds / length.inMilliseconds
        : 0.0;
    final position = current ? audio.position : Duration.zero;
    return _pill(
      color: chatVoicePreviewColor,
      children: [
        _circle(
          key: const ValueKey('chat-voice-preview-toggle'),
          tooltip: playing ? 'Pause voice note' : 'Play voice note',
          color: chatVoicePlayCircleColor,
          onTap: uploading ? null : audio.previewDraft,
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: DarkColors.primaryColor,
            size: AppSizes.chatVoiceIconSize,
          ),
        ),
        SizedBox(width: AppSizes.chatVoiceGap),
        Expanded(
          child: ChatWaveform(
            samples: draft.waveform,
            progress: progress,
            playedColor: DarkColors.primaryColor,
            onSeek: current
                ? (f) => audio.seek(ChatAudioController.draftId, f)
                : null,
          ),
        ),
        SizedBox(width: AppSizes.chatVoiceGap),
        _timer(
          current && (playing || position > Duration.zero)
              ? length - position
              : total,
        ),
      ],
    );
  }
}
