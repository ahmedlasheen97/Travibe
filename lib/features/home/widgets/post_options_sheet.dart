import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/options_sheet.dart';

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
  PostOptionAction.notInterested,
  PostOptionAction.hidePost,
  PostOptionAction.report,
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
    return showOptionsSheet<PostOptionAction>(
      context,
      builder: (_) => PostOptionsSheet(
        actions: actions,
        commentsDisabled: commentsDisabled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    void pick(PostOptionAction action) => Navigator.pop(context, action);
    return OptionsSheetBody(
      children: [
        if (actions.contains(PostOptionAction.toggleComments))
          OptionSheetTile(
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
          OptionSheetTile(
            key: const ValueKey('post-option-copy-link'),
            icon: optionSvg('assets/images/icons/link-2.svg'),
            label: 'Copy link',
            onTap: () => pick(PostOptionAction.copyLink),
          ),
        if (actions.contains(PostOptionAction.deletePost))
          OptionSheetTile(
            key: const ValueKey('post-option-delete'),
            icon: optionSvg(
              'assets/images/icons/trash.svg',
              tint: DarkColors.dangerColor,
            ),
            label: 'Delete post',
            color: DarkColors.dangerColor,
            onTap: () => pick(PostOptionAction.deletePost),
          ),
        if (actions.contains(PostOptionAction.notInterested))
          OptionSheetTile(
            key: const ValueKey('post-option-not-interested'),
            icon: optionSvg(
              'assets/images/icons/slash.svg',
              tint: DarkColors.greyColor,
            ),
            label: 'Not interested',
            onTap: () => pick(PostOptionAction.notInterested),
          ),
        if (actions.contains(PostOptionAction.hidePost))
          OptionSheetTile(
            key: const ValueKey('post-option-hide'),
            icon: optionSvg(
              'assets/images/onboarding/eye-slash.svg',
              tint: DarkColors.greyColor,
            ),
            label: 'Hide post',
            onTap: () => pick(PostOptionAction.hidePost),
          ),
        if (actions.contains(PostOptionAction.report))
          OptionSheetTile(
            key: const ValueKey('post-option-report'),
            icon: optionSvg(
              'assets/images/icons/flag.svg',
              tint: DarkColors.greyColor,
            ),
            label: 'Report',
            onTap: () => pick(PostOptionAction.report),
          ),
        if (actions.contains(PostOptionAction.blockUser))
          OptionSheetTile(
            key: const ValueKey('post-option-block'),
            icon: optionSvg(
              'assets/images/icons/user-remove.svg',
              tint: DarkColors.dangerColor,
            ),
            label: 'Block user',
            color: DarkColors.dangerColor,
            onTap: () => pick(PostOptionAction.blockUser),
          ),
      ],
    );
  }
}
