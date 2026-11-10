import 'package:travibe/core/widgets/user_profile_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/utils/formatters.dart';
import 'package:travibe/features/comments/data/comment_model.dart';

// Explicit styles prevent the app's legacy title decorations from leaking in.
const commentTextStyle = TextStyle(
  fontFamily: 'Plus Jakarta Sans',
  fontSize: 14,
  height: 24 / 14,
  fontWeight: FontWeight.w400,
  color: DarkColors.whiteColor,
  decoration: TextDecoration.none,
  letterSpacing: 0,
);
const commentMutedColor = Color(0xFF989693);

class CommentAction extends StatelessWidget {
  const CommentAction({super.key, required this.label, this.onTap, this.icon});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(32),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                style: commentTextStyle.copyWith(
                  color: commentMutedColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 8),
              Icon(icon, size: 20, color: commentMutedColor),
            ],
          ],
        ),
      ),
    ),
  );
}

class CommentRow extends StatelessWidget {
  const CommentRow({
    super.key,
    required this.comment,
    required this.busy,
    required this.onReply,
    required this.onToggleReplies,
    required this.onEdit,
    required this.onDelete,
    required this.expanded,
    this.onLike,
    this.likePending = false,
  });
  final CommentModel comment;
  final bool busy;
  final bool expanded;
  final VoidCallback? onLike;
  final bool likePending;
  final VoidCallback? onReply;
  final VoidCallback onToggleReplies;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final avatar = comment.user?.avatarUrl;
    final timestamp = timeAgo(comment.createdAt);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        UserProfileLink(
          userId: comment.user?.id,
          child: ClipOval(
            child: SizedBox.square(
              dimension: 32,
              child: avatar == null || avatar.isEmpty
                  ? const _AvatarFallback()
                  : Image.network(
                      avatar,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const _AvatarFallback(),
                    ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  UserProfileLink(
                    userId: comment.user?.id,
                    child: Text(
                      comment.user?.name ?? 'User',
                      style: commentTextStyle.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (timestamp.isNotEmpty)
                    Text(
                      timestamp,
                      style: commentTextStyle.copyWith(
                        fontSize: 12,
                        height: 16 / 12,
                        color: commentMutedColor,
                      ),
                    ),
                ],
              ),
              Text(comment.content ?? 'Media comment', style: commentTextStyle),
              CommentAction(label: 'Reply', onTap: onReply),
              if (expanded ||
                  comment.repliesCount == null ||
                  comment.repliesCount! > 0)
                CommentAction(
                  label: expanded
                      ? 'Hide replies'
                      : comment.repliesCount == null
                      ? 'View replies'
                      : 'View ${comment.repliesCount} replies',
                  icon: expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  onTap: onToggleReplies,
                ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Column(
          children: [
            Semantics(
              button: true,
              toggled: comment.isLiked == true,
              enabled: !busy && !likePending && onLike != null,
              onTap: busy || likePending ? null : onLike,
              label:
                  '${comment.isLiked == true ? 'Unlike' : 'Like'} comment, ${comment.likesCount ?? 0} likes',
              child: ExcludeSemantics(
                child: InkWell(
                  key: ValueKey('comment-like-${comment.id}'),
                  onTap: busy || likePending ? null : onLike,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SvgPicture.asset(
                          comment.isLiked == true
                              ? 'assets/images/interactions/heart.svg'
                              : 'assets/images/interactions/heart2.svg',
                          width: 20,
                          height: 20,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          formatCount(comment.likesCount ?? 0),
                          style: commentTextStyle.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (comment.permissions.canEdit || comment.permissions.canDelete)
              SizedBox(
                height: 32,
                child: PopupMenuButton<String>(
                  tooltip: 'Comment options',
                  padding: EdgeInsets.zero,
                  icon: const Icon(
                    Icons.more_horiz,
                    color: commentMutedColor,
                    size: 20,
                  ),
                  enabled: !busy,
                  onSelected: (action) =>
                      action == 'edit' ? onEdit() : onDelete(),
                  itemBuilder: (_) => [
                    if (comment.permissions.canEdit)
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    if (comment.permissions.canDelete)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback();
  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: DarkColors.darkgreyColor,
    child: Icon(Icons.person_outline, size: 20, color: DarkColors.greyColor),
  );
}
