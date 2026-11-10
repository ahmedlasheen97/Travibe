import 'package:flutter/material.dart';
import '../cubit/chat_audio_controller.dart';
import 'package:travibe/core/theme/dark_colors.dart';

class ChatRecordingStrip extends StatelessWidget {
  const ChatRecordingStrip({super.key, required this.audio});
  final ChatAudioController audio;
  @override
  Widget build(BuildContext context) {
    final seconds = audio.recordingDuration.inSeconds;
    return Row(
      children: [
        IconButton(
          tooltip: 'Cancel recording',
          onPressed: audio.cancelRecording,
          icon: const Icon(Icons.delete_outline, color: Colors.white70),
        ),
        Text(
          '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Semantics(
            label: 'Live microphone level',
            child: SizedBox(
              height: 32,
              child: CustomPaint(painter: _Levels(List.of(audio.levels))),
            ),
          ),
        ),
        IconButton(
          tooltip: audio.recordingPaused
              ? 'Resume recording'
              : 'Pause recording',
          onPressed: audio.pauseRecording,
          icon: Icon(
            audio.recordingPaused ? Icons.mic : Icons.pause,
            color: DarkColors.primaryColor,
          ),
        ),
      ],
    );
  }
}

class _Levels extends CustomPainter {
  const _Levels(this.samples);
  final List<double> samples;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = DarkColors.primaryColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < samples.length; i++) {
      final x = size.width - (samples.length - i) * size.width / 32;
      final height = 2 + samples[i] * (size.height - 2);
      canvas.drawLine(
        Offset(x, (size.height - height) / 2),
        Offset(x, (size.height + height) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Levels old) => true;
}
