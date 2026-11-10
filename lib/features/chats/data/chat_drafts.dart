import 'package:travibe/core/datasource/localdata/preferences_manager.dart';

/// Memory-only drafts survive route changes, never logout/account changes.
class ChatDrafts {
  ChatDrafts._() {
    PreferencesManager().addListener(_values.clear);
  }
  static final instance = ChatDrafts._();
  final Map<String, String> _values = {};
  String read(String conversation) => _values[conversation] ?? '';
  void write(String conversation, String text) {
    if (text.isEmpty) {
      _values.remove(conversation);
    } else {
      _values[conversation] = text;
    }
  }
}
