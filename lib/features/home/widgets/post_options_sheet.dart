import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/sheet_handle.dart';

enum PostOptionAction {
  notInterested,
  hidePost,
  report,
  blockUser,
  // Own post only.
  toggleComments,
  copyLink,
  deletePost,
}

/// Actions on someone else's post.
const otherPostActions = {
  PostOptionAction.hidePost,
  PostOptionAction.blockUser,
};

/// Actions on the viewer's own post (Figma: own post menu).
const ownPostActions = {
  PostOptionAction.toggleComments,
  PostOptionAction.copyLink,
  PostOptionAction.deletePost,
};

class PostOptionsSheet extends StatelessWidget {
  const PostOptionsSheet({
    super.key,
    this.actions = const {
      PostOptionAction.notInterested,
      PostOptionAction.hidePost,
      PostOptionAction.report,
      PostOptionAction.blockUser,
    },
    this.commentsDisabled = false,
  });

  final Set<PostOptionAction> actions;

  /// Switches the commenting row to "Turn on commenting".
  final bool commentsDisabled;

  static Future<PostOptionAction?> show(
    BuildContext context, {
    Set<PostOptionAction> actions = const {
      PostOptionAction.notInterested,
      PostOptionAction.hidePost,
      PostOptionAction.report,
      PostOptionAction.blockUser,
    },
    bool commentsDisabled = false,
  }) {
    return showModalBottomSheet<PostOptionAction>(
      context: context,
      backgroundColor: _sheetColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => PostOptionsSheet(
        actions: actions,
        commentsDisabled: commentsDisabled,
      ),
    );
  }

  // Figma own-post menu frame.
  static const _sheetColor = Color(0xFF0A0A0A);

  static Widget _svg(String path, {Color? tint}) => SvgPicture.asset(
    path,
    width: 24,
    height: 24,
    colorFilter: tint == null ? null : ColorFilter.mode(tint, BlendMode.srcIn),
  );

  @override
  Widget build(BuildContext context) {
    void pick(PostOptionAction action) => Navigator.pop(context, action);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          const SheetHandle(),
          const SizedBox(height: 16),
          if (actions.contains(PostOptionAction.toggleComments))
            _OptionTile(
              key: const ValueKey('post-option-toggle-comments'),
              // No "comment off" icon in assets/images/icons/ yet.
              icon: Icon(
                commentsDisabled
                    ? Icons.comment_outlined
                    : Icons.comments_disabled_outlined,
                color: DarkColors.greyColor,
                size: 24,
              ),
              label: commentsDisabled
                  ? 'Turn on commenting'
                  : 'Turn off commenting',
              onTap: () => pick(PostOptionAction.toggleComments),
            ),
          if (actions.contains(PostOptionAction.copyLink))
            _OptionTile(
              key: const ValueKey('post-option-copy-link'),
              icon: _svg('assets/images/icons/link-2.svg'),
              label: 'Copy link',
              onTap: () => pick(PostOptionAction.copyLink),
            ),
          if (actions.contains(PostOptionAction.deletePost))
            _OptionTile(
              key: const ValueKey('post-option-delete'),
              icon: _svg(
                'assets/images/icons/trash.svg',
                tint: DarkColors.dangerColor,
              ),
              label: 'Delete post',
              color: DarkColors.dangerColor,
              onTap: () => pick(PostOptionAction.deletePost),
            ),
          if (actions.contains(PostOptionAction.notInterested))
            _OptionTile(
              icon: const Icon(
                Icons.block_rounded,
                color: DarkColors.greyColor,
                size: 24,
              ),
              label: 'Not interested',
              onTap: () => pick(PostOptionAction.notInterested),
            ),
          if (actions.contains(PostOptionAction.hidePost))
            _OptionTile(
              key: const ValueKey('post-option-hide'),
              icon: const Icon(
                Icons.visibility_off_outlined,
                color: DarkColors.greyColor,
                size: 24,
              ),
              label: 'Hide post',
              onTap: () => pick(PostOptionAction.hidePost),
            ),
          if (actions.contains(PostOptionAction.report))
            _OptionTile(
              icon: const Icon(
                Icons.flag_outlined,
                color: DarkColors.greyColor,
                size: 24,
              ),
              label: 'Report',
              onTap: () => pick(PostOptionAction.report),
            ),
          if (actions.contains(PostOptionAction.blockUser))
            _OptionTile(
              key: const ValueKey('post-option-block'),
              icon: const Icon(
                Icons.person_off_outlined,
                color: DarkColors.dangerColor,
                size: 24,
              ),
              label: 'Block user',
              color: DarkColors.dangerColor,
              onTap: () => pick(PostOptionAction.blockUser),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final Widget icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _OptionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        children: [
          SizedBox.square(dimension: 24, child: Center(child: icon)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                color: color ?? DarkColors.whiteColor,
                fontSize: 16,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
