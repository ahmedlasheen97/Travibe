import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/options_sheet.dart';

enum ChatMessageAction { copy, deleteForMe, deleteForEveryone, report }

/// Long-press menu on a chat message (Figma: chat/message_menu): handle,
/// then only the rows that apply.
class ChatMessageOptionsSheet extends StatelessWidget {
  const ChatMessageOptionsSheet({super.key, required this.actions});

  final Set<ChatMessageAction> actions;

  static Future<ChatMessageAction?> show(
    BuildContext context, {
    required Set<ChatMessageAction> actions,
  }) => showOptionsSheet<ChatMessageAction>(
    context,
    builder: (_) => ChatMessageOptionsSheet(actions: actions),
  );

  @override
  Widget build(BuildContext context) {
    Widget row(
      ChatMessageAction action,
      Widget icon,
      String label, {
      Color? color,
    }) => OptionSheetTile(
      key: ValueKey('chat-message-option-${action.name}'),
      icon: icon,
      label: label,
      color: color,
      onTap: () => Navigator.of(context).pop(action),
    );

    return OptionsSheetBody(
      children: [
        if (actions.contains(ChatMessageAction.copy))
          row(
            ChatMessageAction.copy,
            optionSvg('assets/images/icons/copy.svg'),
            'Copy message',
          ),
        if (actions.contains(ChatMessageAction.deleteForMe))
          row(
            ChatMessageAction.deleteForMe,
            optionSvg('assets/images/icons/trash.svg'),
            'Delete for me',
          ),
        if (actions.contains(ChatMessageAction.deleteForEveryone))
          row(
            ChatMessageAction.deleteForEveryone,
            optionSvg(
              'assets/images/icons/trash.svg',
              tint: DarkColors.dangerColor,
            ),
            'Delete for everyone',
            color: DarkColors.dangerColor,
          ),
        if (actions.contains(ChatMessageAction.report))
          row(
            ChatMessageAction.report,
            optionSvg('assets/images/icons/flag.svg'),
            'Report',
          ),
      ],
    );
  }
}
