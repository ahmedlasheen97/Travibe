import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/block/widgets/block_user_button.dart';
import 'package:travibe/features/profile/screens/profile_screen.dart';
import 'package:travibe/features/profile/data/profile_repo.dart';
import 'package:travibe/features/home/widgets/report_reason_sheet.dart';
import '../data/chat_models.dart';

enum ChatOption { profile, delete, report, block }

class ChatOptionsSheet extends StatelessWidget {
  const ChatOptionsSheet({super.key, this.canDelete = true});
  final bool canDelete;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 16),
            for (final option in ChatOption.values)
              if (option != ChatOption.delete || canDelete) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: SvgPicture.asset(
                    'assets/images/icons/${switch (option) {
                      ChatOption.profile => 'profilepersonicon.svg',
                      ChatOption.delete => 'trash.svg',
                      ChatOption.report => 'flag.svg',
                      ChatOption.block => 'user_remove_2.svg',
                    }}',
                    width: 24,
                    height: 24,
                    colorFilter: ColorFilter.mode(
                      option == ChatOption.block
                          ? Colors.redAccent
                          : Colors.white,
                      BlendMode.srcIn,
                    ),
                  ),
                  title: Text(
                    switch (option) {
                      ChatOption.profile => 'View user profile',
                      ChatOption.delete => 'Delete chat',
                      ChatOption.report => 'Report',
                      ChatOption.block => 'Block user',
                    },
                    style: TextStyle(
                      color: option == ChatOption.block
                          ? Colors.redAccent
                          : Colors.white,
                      fontSize: 16,
                    ),
                  ),
                  onTap: () => Navigator.pop(context, option),
                ),
                if (option != ChatOption.block)
                  const Divider(height: 1, color: Colors.white10),
              ],
          ],
        ),
      ),
    ),
  );
}

/// Reuse the existing Profile report API, reason picker and shared Block flow.
Future<void> chatUserAction(
  BuildContext context,
  ChatConversation conversation,
  ChatOption action, {
  ProfileRepo? profiles,
}) async {
  final prefs = PreferencesManager(),
      session = PreferencesManager().sessionRevision;
  bool active() =>
      context.mounted && prefs.hasSession && session == prefs.sessionRevision;
  final participant = conversation.participant;
  final id = int.tryParse(participant.id);
  if (!active() || id == null || id <= 0) return;
  try {
    switch (action) {
      case ChatOption.profile:
        await ProfileScreen.open(context, userId: id, profileRepo: profiles);
      case ChatOption.report:
        final report = await ReportReasonSheet.show(context);
        if (!context.mounted || !active() || report == null) return;
        await (profiles ?? ProfileRepo()).reportUser(
          participant.id,
          report.reason.apiValue,
        );
        if (context.mounted && active()) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Report submitted.')));
        }
      case ChatOption.block:
        if (context.read<BlockCubit?>() == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'User actions are unavailable. Please reopen this conversation.',
              ),
            ),
          );
          return;
        }
        await confirmBlockChange(
          context,
          participant.id,
          blocked: true,
          name: participant.name,
        );
      case ChatOption.delete:
        return;
    }
  } catch (_) {
    if (context.mounted && active()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to complete this action. Please try again.'),
        ),
      );
    }
  }
}
