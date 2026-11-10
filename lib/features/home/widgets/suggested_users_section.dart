import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/block/widgets/refresh_users_on_unblock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/widgets/error_retry_view.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_users_cubit.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';
import 'package:travibe/features/follow/screens/follow_users_screen.dart';
import 'package:travibe/features/follow/widgets/follow_user_tile.dart';
import 'package:travibe/features/home/widgets/suggested_user_card.dart';

class SuggestedUsersSection extends StatelessWidget {
  const SuggestedUsersSection({
    super.key,
    this.compact = false,
    this.showLoadingIndicators = true,
    this.currentUserId,
    this.cubit,
  });
  final bool compact;
  // Home suppresses independent spinners; Search retains its current behavior.
  final bool showLoadingIndicators;
  final String? currentUserId;
  final FollowUsersCubit? cubit;

  @override
  Widget build(BuildContext context) {
    final child = _content(context);
    if (cubit != null) return BlocProvider.value(value: cubit!, child: child);
    return BlocProvider(
      create: (_) => FollowUsersCubit(
        type: FollowListType.suggested,
        repo: context.read<FollowCubit>().repo,
      )..load(),
      child: child,
    );
  }

  Widget _content(BuildContext context) => RefreshUsersOnUnblock(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                compact ? 'Suggested for You' : 'Suggested for you',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: () => FollowUsersScreen.open(
                context,
                type: FollowListType.suggested,
              ),
              child: Text(
                'See All',
                style: compact
                    ? const TextStyle(color: Colors.white70, fontSize: 14)
                    : null,
              ),
            ),
          ],
        ),
        BlocBuilder<FollowUsersCubit, FollowUsersState>(
          builder: (context, state) {
            final cubit = context.read<FollowUsersCubit>();
            if (state.status == FollowUsersStatus.initial ||
                state.status == FollowUsersStatus.loading) {
              return showLoadingIndicators
                  ? const Center(child: CircularProgressIndicator())
                  : const SizedBox.shrink();
            }
            if (state.status == FollowUsersStatus.failure ||
                (!compact && state.error != null)) {
              return ErrorRetryView(
                message: state.error!.message,
                onRetry: cubit.load,
              );
            }
            return BlocBuilder<BlockCubit, BlockState>(
              builder: (context, block) =>
                  BlocBuilder<FollowCubit, FollowState>(
                    builder: (context, follow) {
                      final users = state.users
                          .where(
                            (user) =>
                                !block.isBlocked(
                                  user.id,
                                  fallback: user.isBlocked,
                                ) &&
                                user.id != currentUserId &&
                                user.id.isNotEmpty &&
                                (compact ||
                                    !(follow.following[user.id] ??
                                        user.isFollowing)),
                          )
                          .toList();
                      final unique = {
                        for (final user in users) user.id: user,
                      }.values.toList();
                      if (compact) return _cards(context, state, unique);
                      return Column(
                        children: [
                          if (users.isEmpty)
                            const Text('No suggestions right now'),
                          for (final user in unique.take(3))
                            FollowUserTile(key: ValueKey(user.id), user: user),
                        ],
                      );
                    },
                  ),
            );
          },
        ),
      ],
    ),
  );
  Widget _cards(
    BuildContext context,
    FollowUsersState state,
    List<PublicUserModel> users,
  ) {
    final list = context.read<FollowUsersCubit>();
    return Column(
      children: [
        if (state.refreshing && showLoadingIndicators)
          const LinearProgressIndicator(minHeight: 2),
        if (state.error != null)
          ErrorRetryView(message: state.error!.message, onRetry: list.load),
        if (users.isEmpty && !state.hasMore)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No suggestions right now',
              style: TextStyle(color: Colors.white54),
            ),
          ),
        if (users.isNotEmpty || state.hasMore)
          SizedBox(
            height: SuggestedUserCard.heightFor(
              MediaQuery.textScalerOf(context),
            ),
            child: NotificationListener<ScrollNotification>(
              onNotification: (event) {
                if (event.metrics.axis == Axis.horizontal &&
                    event.metrics.extentAfter < 160) {
                  list.more();
                }
                return false;
              },
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: users.length + (state.hasMore ? 1 : 0),
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  if (index < users.length) {
                    return SuggestedUserCard(
                      key: ValueKey(users[index].id),
                      user: users[index],
                    );
                  }
                  return SizedBox(
                    width: 144,
                    child: Center(
                      child: state.loadingMore
                          ? (showLoadingIndicators
                                ? const CircularProgressIndicator()
                                : const SizedBox.shrink())
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (state.paginationError != null)
                                  Text(
                                    state.paginationError!.message,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                TextButton(
                                  onPressed: () => list.more(
                                    retry: state.paginationError != null,
                                  ),
                                  child: Text(
                                    state.paginationError == null
                                        ? 'More people'
                                        : 'Retry',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
