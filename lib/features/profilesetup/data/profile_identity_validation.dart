/// Shape rules from ProfileSetupRequest; availability is server-authoritative.
abstract final class ProfileIdentityValidation {
  static String? fullName(String value) {
    final text = value.trim();
    if (text.isEmpty) return 'Full name is required.';
    if (text.runes.length > 255) return 'Use at most 255 characters.';
    return null;
  }

  static String? username(String value) {
    final text = value.trim();
    if (text.isEmpty) return 'Username is required.';
    if (text.length < 3 || text.runes.length > 30) {
      return 'Use 3–30 characters.';
    }
    if (!RegExp(r'^[a-zA-Z0-9_][a-zA-Z0-9_.]*[a-zA-Z0-9_]$').hasMatch(text)) {
      return 'Use letters, numbers, underscores or dots; do not start or end with a dot.';
    }
    return null;
  }
}
