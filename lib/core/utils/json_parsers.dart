bool parseBool(dynamic value) {
  return value == true || value == 'true' || value == 1 || value == '1';
}

int parseInt(dynamic value, {int fallback = 0}) {
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

List<String> parseStringList(dynamic value) {
  if (value is! List) return const [];
  return value
      .map(
        (e) => e is Map
            ? (e['name'] ?? e['label'])?.toString() ?? ''
            : e.toString(),
      )
      .where((s) => s.isNotEmpty)
      .toList();
}

/// A backend share link (`url`): https with a host and no credentials,
/// otherwise null. Used as-is; the app never builds these links.
Uri? parseHttpsUri(dynamic value) {
  final uri = value is String ? Uri.tryParse(value.trim()) : null;
  return uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? uri
      : null;
}
