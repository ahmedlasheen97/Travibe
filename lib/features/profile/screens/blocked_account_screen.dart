import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/error_retry_view.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/block/widgets/block_user_button.dart';
import 'package:travibe/features/block/widgets/refresh_users_on_unblock.dart';
import 'package:travibe/features/follow/cubit/follow_users_cubit.dart';

class BlockedAccountsScreen extends StatelessWidget {
  const BlockedAccountsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) =>
        FollowUsersCubit(loadPage: context.read<BlockCubit>().loadUsers)
          ..load(),
    child: RefreshUsersOnUnblock(
      onAnyMutation: true,
      child: Scaffold(
        backgroundColor: DarkColors.backgroundColor,
        appBar: AppBar(
          leading: Navigator.of(context).canPop()
              ? const BackButtonWidget()
              : null,
          title: const Text('Blocked Accounts'),
        ),
        body: BlocBuilder<FollowUsersCubit, FollowUsersState>(
          builder: (context, state) {
            final list = context.read<FollowUsersCubit>();
            if (state.status == FollowUsersStatus.initial ||
                state.status == FollowUsersStatus.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.status == FollowUsersStatus.failure) {
              return ErrorRetryView(
                message: state.error!.message,
                onRetry: list.load,
              );
            }
            return BlocBuilder<BlockCubit, BlockState>(
              builder: (context, block) {
                final users = state.users
                    .where((u) => block.isBlocked(u.id, fallback: true))
                    .toList();
                return RefreshIndicator(
                  onRefresh: list.load,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (event) {
                      if (event.metrics.extentAfter < 300) list.more();
                      return false;
                    },
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(
                          child: Column(
                            children: [
                              if (state.refreshing)
                                const LinearProgressIndicator(),
                              if (state.error != null)
                                ErrorRetryView(
                                  message: state.error!.message,
                                  onRetry: list.load,
                                ),
                              if (users.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text('No blocked accounts'),
                                ),
                            ],
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          sliver: SliverList.builder(
                            itemCount: users.length,
                            itemBuilder: (context, index) => _BlockedUserTile(
                              user:
                                  block.users[users[index].id] ?? users[index],
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Column(
                            children: [
                              if (state.loadingMore)
                                const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              if (state.paginationError != null)
                                ErrorRetryView(
                                  message: state.paginationError!.message,
                                  onRetry: () => list.more(retry: true),
                                ),
                              if (state.hasMore &&
                                  !state.loadingMore &&
                                  state.paginationError == null)
                                TextButton(
                                  onPressed: list.more,
                                  child: const Text('Load more'),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    ),
  );
}

class _BlockedUserTile extends StatelessWidget {
  const _BlockedUserTile({required this.user});
  final PublicUserModel user;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFF141414),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundImage: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
              ? NetworkImage(user.avatarUrl!)
              : null,
          child: user.avatarUrl == null || user.avatarUrl!.isEmpty
              ? const Icon(Icons.person)
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(user.handle, style: const TextStyle(color: Colors.white54)),
              if (user.isFollowing)
                const Text(
                  'Following',
                  style: TextStyle(color: Colors.white54),
                ),
            ],
          ),
        ),
        BlockUserButton(userId: user.id, initialBlocked: true, name: user.name),
      ],
    ),
  );
}
