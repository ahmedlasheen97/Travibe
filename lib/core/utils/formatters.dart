String formatCount(int count) {
  String trimmed(double value) =>
      value.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');

  if (count >= 1000000) return '${trimmed(count / 1000000)}M';
  if (count >= 1000) return '${trimmed(count / 1000)}K';
  return '$count';
}

String timeAgo(DateTime? date) {
  if (date == null) return '';
  final diff = DateTime.now().difference(date);

  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}min';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return '${diff.inDays ~/ 7}w';
}