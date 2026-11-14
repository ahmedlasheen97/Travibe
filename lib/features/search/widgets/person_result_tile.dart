import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/core/utils/viewer_identity.dart';
import 'package:travibe/core/widgets/user_profile_link.dart';
import 'package:travibe/features/follow/widgets/follows_you_badge.dart';
import 'package:travibe/features/home/widgets/home_user_avatar.dart';

class PersonResultTile extends StatelessWidget {
  final PublicUserModel user;
  final VoidCallback? onFollowTap;
  final bool isFollowingPending;
  final VoidCallback? onTap;
  final bool followsYou;
  final Widget? trailing;

  /// False hides the follow pill (e.g. when the tile is a picker row).
  final bool showFollow;

  const PersonResultTile({
    super.key,
    required this.user,
    required this.onFollowTap,
    this.onTap,
    this.isFollowingPending = false,
    this.followsYou = false,
    this.trailing,
    this.showFollow = true,
  });

  @override
  Widget build(BuildContext context) {
    // The signed-in user's own row never offers Follow/Requested, "Follows
    // you" or ⋮ user actions, and opens their Profile tab.
    final own = isViewer(context, user.id);
    final badge = followsYou && !own;
    return InkWell(
      key: own ? const ValueKey('own-user-row') : null,
      onTap: own ? () => openUserProfile(context, user.id) : onTap,
      borderRadius: BorderRadius.circular(AppSizes.r20),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: AppSizes.pw12,
          vertical: AppSizes.ph12,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(AppSizes.r20),
        ),
        // Figma: the "Follows you" pill sits above the picture row.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badge) ...[
              const FollowsYouBadge(compact: true),
              SizedBox(height: AppSizes.h6),
            ],
            LayoutBuilder(
              builder: (context, constraints) => Row(
                children: [
                  HomeUserAvatar(url: user.avatarUrl, size: AppSizes.w44),
                  SizedBox(width: AppSizes.w12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: AppSizes.sp15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (user.handle.isNotEmpty)
                          Text(
                            user.handle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: AppSizes.sp13,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (showFollow && !own) ...[
                    SizedBox(width: AppSizes.w12),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: trailing == null
                            ? constraints.maxWidth / 2
                            : (constraints.maxWidth / 2).clamp(
                                0,
                                AppSizes.w112,
                              ),
                      ),
                      child: InkWell(
                        key: ValueKey('follow-pill-${user.id}'),
                        onTap: onFollowTap,
                        borderRadius: BorderRadius.circular(AppSizes.r20),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: AppSizes.pw18,
                            vertical: AppSizes.ph8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A2A2A),
                            borderRadius: BorderRadius.circular(AppSizes.r20),
                          ),
                          child: Text(
                            isFollowingPending
                                ? 'Updating…'
                                : user.isFollowing
                                ? 'Following'
                                : user.followRequested
                                ? 'Requested'
                                : 'Follow',
                            maxLines: trailing == null ? null : 1,
                            overflow: trailing == null
                                ? null
                                : TextOverflow.ellipsis,
                            style: TextStyle(
                              color:
                                  !isFollowingPending &&
                                      !user.isFollowing &&
                                      user.followRequested
                                  ? const Color(0xFF989693)
                                  : Colors.white,
                              fontSize: AppSizes.sp14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (!own) ?trailing,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
