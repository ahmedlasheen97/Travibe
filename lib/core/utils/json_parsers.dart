bool parseBool(dynamic value) {
  return value == true ||
      value == 'true' ||
      value == 1 ||
      value == '1';
}

int parseInt(dynamic value, {int fallback = 0}) {
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}
List<String> parseStringList(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((e) => e is Map ? (e['name'] ?? e['label'])?.toString() ?? '' : e.toString())
      .where((s) => s.isNotEmpty)
      .toList();
}