import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_users_cubit.dart';

/// Runs inside the list's provider; avoids accepting a pre-unblock page as fresh.
class RefreshUsersOnUnblock extends StatelessWidget {
  const RefreshUsersOnUnblock({
    super.key,
    required this.child,
    this.onAnyMutation = false,
  });
  final Widget child;
  final bool onAnyMutation;

  @override
  Widget build(BuildContext context) => BlocListener<BlockCubit, BlockState>(
    listenWhen: (previous, current) => onAnyMutation
        ? previous.mutationRevision != current.mutationRevision
        : previous.unblockRevision != current.unblockRevision,
    listener: (context, _) async {
      final list = context.read<FollowUsersCubit>();
      await list.pendingLoad;
      if (!list.isClosed) await list.load();
    },
    child: child,
  );
}
