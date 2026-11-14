import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/utils/formatters.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/block/widgets/block_user_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';
import 'package:travibe/features/follow/screens/follow_users_screen.dart';
import 'package:travibe/features/follow/widgets/follow_action_builder.dart';
import 'package:travibe/features/search/widgets/person_result_tile.dart';
import 'package:travibe/features/profile/screens/profile_screen.dart';

/// A people row: rounded card with the shared follow pill.
/// Followers/Following lists drop the ⋮ menu (suggested rows keep it), show
/// "Follows you" only on a Following list, and [onRemove] adds the X that
/// removes one of my followers.
class FollowUserTile extends StatelessWidget {
  const FollowUserTile({
    super.key,
    required this.user,
    this.listType = FollowListType.suggested,
    this.onRemove,
  });
  final PublicUserModel user;
  final FollowListType listType;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => FollowActionBuilder(
    userId: user.id,
    initialFollowing: user.isFollowing,
    initialRequested: user.followRequested,
    builder: (context, relation, pending, onToggle) {
      final follow = context.read<FollowCubit>().state;
      final current = follow.users[user.id] ?? user;
      return BlocBuilder<BlockCubit, BlockState>(
        builder: (context, block) {
          final blocked = block.isBlocked(user.id, fallback: current.isBlocked);
          final id = int.tryParse(user.id);
          return Padding(
            padding: EdgeInsets.only(bottom: AppSizes.ph10),
            child: PersonResultTile(
              user: current.copyWith(
                isFollowing: relation.isFollowing,
                followRequested: relation.isRequested,
              ),
              followsYou:
                  listType != FollowListType.followers &&
                  (follow.followsYou[user.id] ?? current.followsYou),
              onTap: id == null || id < 1
                  ? null
                  : () => ProfileScreen.open(context, userId: id),
              onFollowTap: blocked || block.pending.contains(user.id)
                  ? null
                  : onToggle,
              isFollowingPending: pending,
              trailing: listType != FollowListType.suggested
                  ? _remove(follow)
                  : PopupMenuButton<String>(
                      tooltip: 'User options',
                      color: DarkColors.darkgreyColor,
                      icon: Icon(
                        Icons.more_vert,
                        color: Colors.white54,
                        size: AppSizes.w20,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints(minWidth: AppSizes.w160),
                      onSelected: (action) {
                        if (action == 'block') {
                          confirmBlockChange(
                            context,
                            user.id,
                            blocked: !blocked,
                            name: user.name,
                          );
                        } else {
                          FollowUsersScreen.open(
                            context,
                            type: action == 'followers'
                                ? FollowListType.followers
                                : FollowListType.following,
                            userId: user.id,
                            username: current.username,
                            followersCount: current.followersCount,
                            followingCount: current.followingCount,
                          );
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'block',
                          enabled: !block.pending.contains(user.id),
                          child: Text(
                            blocked ? 'Unblock' : 'Block',
                            style: TextStyle(
                              color: DarkColors.whiteColor,
                              fontSize: AppSizes.sp14,
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'followers',
                          child: Text(
                            countLabel(current.followersCount, 'follower'),
                            style: TextStyle(
                              color: DarkColors.whiteColor,
                              fontSize: AppSizes.sp14,
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'following',
                          child: Text(
                            '${current.followingCount} following',
                            style: TextStyle(
                              color: DarkColors.whiteColor,
                              fontSize: AppSizes.sp14,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          );
        },
      );
    },
  );

  Widget? _remove(FollowState follow) {
    final remove = onRemove;
    if (remove == null) return null;
    return IconButton(
      key: ValueKey('remove-follower-${user.id}'),
      tooltip: 'Remove follower',
      onPressed: follow.pending.contains(user.id) ? null : remove,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(
        width: AppSizes.w40,
        height: AppSizes.h40,
      ),
      icon: Icon(Icons.close, color: Colors.white70, size: AppSizes.w24),
    );
  }
}
