import 'dart:typed_data';
import 'chat_models.dart';

class ChatMediaSelection {
  ChatMediaSelection(
    this.bytes,
    this.filename,
    this.mime,
    this.kind, {
    this.durationMs,
  });
  final Uint8List bytes;
  final String filename, mime;
  final ChatMessageKind kind;
  final int? durationMs;
  int? readyId;
  bool sendUncertain = false;
  String? caption, replyTo;
}

/// User-ordered, memory-only selection. Confirmed items leave individually;
/// a failure retains the current item and all subsequent items.
class ChatMediaSelectionQueue {
  final List<ChatMediaSelection> _items = [];
  List<ChatMediaSelection> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;
  ChatMediaSelection get first => _items.first;
  void addAll(Iterable<ChatMediaSelection> values) {
    final all = [..._items, ...values];
    if (all.length > 10 ||
        all.fold<int>(0, (n, m) => n + m.bytes.length) > 100 * 1024 * 1024) {
      throw const FormatException(
        'Select up to 10 attachments totaling no more than 100 MB.',
      );
    }
    _items.addAll(values);
  }

  void remove(ChatMediaSelection value) => _items.remove(value);
  void clear() => _items.clear();
}
