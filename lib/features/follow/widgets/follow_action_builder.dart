import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';

/// Keeps every occurrence of a user in sync without mutating feed/search models.
class FollowActionBuilder extends StatelessWidget {
  const FollowActionBuilder({
    super.key,
    required this.userId,
    required this.initialFollowing,
    required this.builder,
  });
  final String userId;
  final bool initialFollowing;
  final Widget Function(
    BuildContext,
    bool following,
    bool pending,
    VoidCallback? onToggle,
  )
  builder;

  @override
  Widget build(BuildContext context) => BlocBuilder<FollowCubit, FollowState>(
    builder: (context, state) {
      final following = state.following[userId] ?? initialFollowing;
      final pending = state.pending.contains(userId);
      final allowed = context.read<FollowCubit>().canInteract(userId);
      return builder(
        context,
        following,
        pending,
        pending || !allowed
            ? null
            : () async {
                final error = await context.read<FollowCubit>().toggle(
                  userId,
                  currentlyFollowing: following,
                );
                if (error != null && context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(error.message)));
                }
              },
      );
    },
  );
}
