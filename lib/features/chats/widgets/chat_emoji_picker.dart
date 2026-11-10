import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';

/// Selection offsets are UTF-16; whole emoji/ZWJ strings are inserted intact.
/// Snap malformed programmatic selections to grapheme boundaries.
TextEditingValue insertChatEmoji(TextEditingValue value, String emoji) {
  final selection = value.selection;
  var start = selection.isValid
      ? selection.start.clamp(0, value.text.length)
      : value.text.length;
  var end = selection.isValid
      ? selection.end.clamp(0, value.text.length)
      : value.text.length;
  var offset = 0;
  for (final cluster in value.text.characters) {
    final next = offset + cluster.length;
    if (start > offset && start < next) {
      start = selection.isCollapsed ? next : offset;
    }
    if (end > offset && end < next) {
      end = next;
    }
    offset = next;
  }
  if (end < start) end = start;
  return TextEditingValue(
    text: value.text.replaceRange(start, end, emoji),
    selection: TextSelection.collapsed(offset: start + emoji.length),
  );
}

List<CategoryEmoji> _englishEmojiSet(Locale _) => emojiSetEnglish;

class ChatEmojiPicker extends StatelessWidget {
  const ChatEmojiPicker({
    super.key,
    required this.onSelected,
    this.height = 220,
  });
  final ValueChanged<String> onSelected;
  final double height;
  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('chat-emoji-picker'),
    padding: const EdgeInsets.only(top: 8),
    child: EmojiPicker(
      onEmojiSelected: (_, emoji) => onSelected(emoji.emoji),
      config: Config(
        height: height,
        emojiSet: _englishEmojiSet,
        emojiViewConfig: EmojiViewConfig(
          columns: (MediaQuery.sizeOf(context).width / 44).floor().clamp(6, 10),
          emojiSizeMax: 24,
          backgroundColor: const Color(0xFF141414),
          recentsLimit: 0,
        ),
        categoryViewConfig: CategoryViewConfig(
          initCategory: Category.SMILEYS,
          recentTabBehavior: RecentTabBehavior.NONE,
          backgroundColor: const Color(0xFF141414),
          indicatorColor: DarkColors.primaryColor,
          iconColorSelected: DarkColors.primaryColor,
          iconColor: Colors.white54,
          dividerColor: Colors.white12,
          tabIndicatorAnimDuration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
        ),
        bottomActionBarConfig: const BottomActionBarConfig(enabled: false),
      ),
    ),
  );
}
