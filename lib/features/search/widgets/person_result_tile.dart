import 'package:flutter/material.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/home/widgets/home_user_avatar.dart';

class PersonResultTile extends StatelessWidget {
  final PublicUserModel user;
  final VoidCallback? onFollowTap;
  final bool isFollowingPending;
  final VoidCallback? onTap;
  final bool followsYou;
  final Widget? trailing;

  const PersonResultTile({
    super.key,
    required this.user,
    required this.onFollowTap,
    this.onTap,
    this.isFollowingPending = false,
    this.followsYou = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(20),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              HomeUserAvatar(url: user.avatarUrl, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (followsYou) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3A2216),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Follows you',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
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
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: trailing == null
                      ? constraints.maxWidth / 2
                      : (constraints.maxWidth / 2).clamp(0, 112),
                ),
                child: InkWell(
                  onTap: onFollowTap,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isFollowingPending
                          ? 'Updating…'
                          : user.isFollowing
                          ? 'Following'
                          : 'Follow',
                      maxLines: trailing == null ? null : 1,
                      overflow: trailing == null ? null : TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
