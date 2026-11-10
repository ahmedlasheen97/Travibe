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

class FollowUserTile extends StatelessWidget {
  const FollowUserTile({super.key, required this.user});
  final PublicUserModel user;

  @override
  Widget build(BuildContext context) => FollowActionBuilder(
    userId: user.id,
    initialFollowing: user.isFollowing,
    builder: (context, following, pending, onToggle) {
      final current = context.read<FollowCubit>().state.users[user.id] ?? user;
      return BlocBuilder<BlockCubit, BlockState>(
        builder: (context, block) {
          final blocked = block.isBlocked(user.id, fallback: current.isBlocked);
          final id = int.tryParse(user.id);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: PersonResultTile(
              user: current.copyWith(isFollowing: following),
              followsYou:
                  context.read<FollowCubit>().state.followsYou[user.id] ??
                  current.followsYou,
              onTap: id == null || id < 1
                  ? null
                  : () => ProfileScreen.open(context, userId: id),
              onFollowTap: blocked || block.pending.contains(user.id)
                  ? null
                  : onToggle,
              isFollowingPending: pending,
              trailing: PopupMenuButton<String>(
                tooltip: 'User options',
                color: DarkColors.darkgreyColor,
                icon: const Icon(
                  Icons.more_vert,
                  color: Colors.white54,
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 160),
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
                      style: const TextStyle(
                        color: DarkColors.whiteColor,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'followers',
                    child: Text(
                      '${current.followersCount} followers',
                      style: const TextStyle(
                        color: DarkColors.whiteColor,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'following',
                    child: Text(
                      '${current.followingCount} following',
                      style: const TextStyle(
                        color: DarkColors.whiteColor,
                        fontSize: 14,
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
}
