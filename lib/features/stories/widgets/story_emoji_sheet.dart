import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/sheet_handle.dart';
import 'package:travibe/features/chats/widgets/chat_emoji_picker.dart';

/// Reuses the Create Post / chat emoji panel; returns one chosen emoji.
Future<String?> showStoryEmojiSheet(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      backgroundColor: DarkColors.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        key: const ValueKey('story-emoji-sheet'),
        padding: const EdgeInsets.fromLTRB(0, 14, 0, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            ChatEmojiPicker(
              height: 320,
              onSelected: (emoji) => Navigator.pop(context, emoji),
            ),
          ],
        ),
      ),
    );
