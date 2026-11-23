import 'dart:math' as math;

/// Bars drawn for a voice note (pills and bubbles).
const chatVoiceWaveformBars = 28;

/// The API stores no waveform, so sent/pending voice notes draw a stable
/// placeholder: the same duration always yields the same bars.
List<double> chatPlaceholderWaveform(
  int? durationMs, {
  int bars = chatVoiceWaveformBars,
}) {
  final random = math.Random(durationMs ?? 0);
  return List.generate(bars, (i) {
    // A gentle envelope keeps the ends lower, like speech.
    final envelope = .55 + .45 * math.sin(math.pi * (i + .5) / bars);
    return (.2 + random.nextDouble() * .8 * envelope).clamp(.15, 1.0);
  }, growable: false);
}

/// Reduces captured microphone levels (0–1) to [bars] peaks normalised to the
/// loudest one; empty input falls back to the placeholder.
List<double> chatDownsampleWaveform(
  List<double> levels, {
  int bars = chatVoiceWaveformBars,
  int? durationMs,
}) {
  if (levels.isEmpty) return chatPlaceholderWaveform(durationMs, bars: bars);
  final peaks = List.generate(bars, (i) {
    final start = (i * levels.length / bars).floor();
    final end = math.max(start + 1, ((i + 1) * levels.length / bars).floor());
    return levels.sublist(start, math.min(end, levels.length)).reduce(math.max);
  }, growable: false);
  final loudest = peaks.reduce(math.max);
  return [
    for (final peak in peaks)
      loudest <= 0 ? .15 : (peak / loudest).clamp(.15, 1.0),
  ];
}
