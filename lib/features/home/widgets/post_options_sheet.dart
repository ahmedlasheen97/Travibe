import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/sheet_handle.dart';

enum PostOptionAction { notInterested, hidePost, report, blockUser }

class PostOptionsSheet extends StatelessWidget {
  const PostOptionsSheet({
    super.key,
    this.actions = const {
      PostOptionAction.notInterested,
      PostOptionAction.hidePost,
      PostOptionAction.report,
      PostOptionAction.blockUser,
    },
  });

  final Set<PostOptionAction> actions;

  static Future<PostOptionAction?> show(
    BuildContext context, {
    Set<PostOptionAction> actions = const {
      PostOptionAction.notInterested,
      PostOptionAction.hidePost,
      PostOptionAction.report,
      PostOptionAction.blockUser,
    },
  }) {
    return showModalBottomSheet<PostOptionAction>(
      context: context,
      backgroundColor: DarkColors.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => PostOptionsSheet(actions: actions),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          const SheetHandle(),
          const SizedBox(height: 12),
          if (actions.contains(PostOptionAction.notInterested))
            _OptionTile(
              icon: Icons.block_rounded,
              label: 'Not interested',
              onTap: () =>
                  Navigator.pop(context, PostOptionAction.notInterested),
            ),
          if (actions.contains(PostOptionAction.hidePost))
            _OptionTile(
              icon: Icons.visibility_off_outlined,
              label: 'Hide post',
              onTap: () => Navigator.pop(context, PostOptionAction.hidePost),
            ),
          if (actions.contains(PostOptionAction.report))
            _OptionTile(
              icon: Icons.flag_outlined,
              label: 'Report',
              onTap: () => Navigator.pop(context, PostOptionAction.report),
            ),
          if (actions.contains(PostOptionAction.blockUser))
            _OptionTile(
              icon: Icons.person_off_outlined,
              label: 'Block user',
              color: const Color(0xFFDB4A3D),
              onTap: () => Navigator.pop(context, PostOptionAction.blockUser),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _OptionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Colors.white;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: color ?? Colors.white70, size: 24),
            const SizedBox(width: 16),
            Text(label, style: TextStyle(color: tint, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
