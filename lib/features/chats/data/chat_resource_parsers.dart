// All parsing failures deliberately omit values: chat data is private.
String chatId(Object? value) {
  if (value is int && value > 0) return '$value';
  if (value is String &&
      value.trim().isNotEmpty &&
      value != '.' &&
      value != '..' &&
      !value.contains('/')) {
    return value;
  }
  throw const FormatException('Invalid chat identifier.');
}

String? chatString(Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  throw const FormatException('Invalid chat text field.');
}

Map<String, dynamic>? chatObject(Object? value) {
  if (value == null) return null;
  if (value is Map && value.keys.every((key) => key is String)) {
    return Map<String, dynamic>.from(value);
  }
  throw const FormatException('Invalid chat object.');
}

int? chatCount(Object? value) {
  if (value == null) return null;
  if (value is int && value >= 0) return value;
  throw const FormatException('Invalid chat count.');
}

bool? chatBool(Object? value) {
  if (value == null) return null;
  if (value is bool) return value;
  if (value == 1 || value == '1') return true;
  if (value == 0 || value == '0') return false;
  throw const FormatException('Invalid chat boolean.');
}

DateTime? chatDate(Object? value) {
  if (value == null) return null;
  final parsed = value is String ? DateTime.tryParse(value) : null;
  if (parsed == null) throw const FormatException('Invalid chat date.');
  return parsed;
}

/// An https URL without credentials, otherwise null.
Uri? chatHttpsUri(Object? value) {
  final uri = value is String ? Uri.tryParse(value) : null;
  return uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? uri
      : null;
}

Object? freezeChatJson(Object? value) {
  if (value is Map) {
    return Map<String, Object?>.unmodifiable({
      for (final entry in value.entries)
        entry.key.toString(): freezeChatJson(entry.value),
    });
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(freezeChatJson));
  }
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  throw const FormatException('Invalid nested chat data.');
}
