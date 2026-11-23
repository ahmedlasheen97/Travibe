import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';

/// `m:ss` for voice notes; negative values show 0:00.
String formatVoiceClock(Duration value) {
  final seconds = value.isNegative ? 0 : value.inSeconds;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// Rounded voice-note bars. Bars before [progress] use [playedColor]; with
/// [onSeek], tapping or dragging reports the touched fraction (0–1).
class ChatWaveform extends StatelessWidget {
  const ChatWaveform({
    super.key,
    required this.samples,
    this.progress = 0,
    this.playedColor = Colors.white,
    this.idleColor = Colors.white,
    this.onSeek,
    this.alignEnd = false,
  });
  final List<double> samples;
  final double progress;
  final Color playedColor, idleColor;
  final ValueChanged<double>? onSeek;

  /// Live recording: newest bars stick to the trailing edge.
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final paint = SizedBox(
      height: AppSizes.chatVoiceWaveHeight,
      child: CustomPaint(
        size: Size.infinite,
        painter: _WaveformPainter(
          samples: samples,
          progress: progress.clamp(0.0, 1.0),
          playedColor: playedColor,
          idleColor: idleColor,
          barWidth: AppSizes.chatVoiceBarWidth,
          gap: AppSizes.chatVoiceBarGap,
          alignEnd: alignEnd,
        ),
      ),
    );
    final seek = onSeek;
    if (seek == null) return paint;
    return LayoutBuilder(
      builder: (context, constraints) {
        void report(Offset local) {
          final width = constraints.maxWidth;
          if (width <= 0) return;
          final x = Directionality.of(context) == TextDirection.rtl
              ? width - local.dx
              : local.dx;
          seek((x / width).clamp(0.0, 1.0));
        }

        return Semantics(
          slider: true,
          label: 'Voice message position',
          value: '${(progress * 100).round()}%',
          child: GestureDetector(
            key: const ValueKey('chat-voice-seek'),
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => report(details.localPosition),
            onHorizontalDragStart: (details) => report(details.localPosition),
            onHorizontalDragUpdate: (details) => report(details.localPosition),
            child: paint,
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.samples,
    required this.progress,
    required this.playedColor,
    required this.idleColor,
    required this.barWidth,
    required this.gap,
    required this.alignEnd,
  });
  final List<double> samples;
  final double progress, barWidth, gap;
  final Color playedColor, idleColor;
  final bool alignEnd;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty || size.width <= 0) return;
    final step = barWidth + gap;
    final fit = ((size.width + gap) / step).floor().clamp(1, 1 << 16);
    final bars = alignEnd
        ? samples.sublist(samples.length > fit ? samples.length - fit : 0)
        : samples;
    final count = bars.length < fit ? bars.length : fit;
    // Static waveforms spread across the width; live ones keep a fixed pitch.
    final pitch = alignEnd || count < 2
        ? step
        : (size.width - barWidth) / (count - 1);
    final origin = alignEnd ? size.width - (count - 1) * pitch - barWidth : 0.0;
    final paint = Paint()
      ..strokeWidth = barWidth
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < count; i++) {
      final sample = bars[(i * bars.length / count).floor()];
      final height =
          barWidth + sample.clamp(0.0, 1.0) * (size.height - barWidth);
      final x = origin + i * pitch + barWidth / 2;
      paint.color = (i + .5) / count <= progress ? playedColor : idleColor;
      canvas.drawLine(
        Offset(x, (size.height - height) / 2 + barWidth / 2),
        Offset(x, (size.height + height) / 2 - barWidth / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.samples != samples ||
      old.progress != progress ||
      old.playedColor != playedColor ||
      old.idleColor != idleColor ||
      old.alignEnd != alignEnd;
}
