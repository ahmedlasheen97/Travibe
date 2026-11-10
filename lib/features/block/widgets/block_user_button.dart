import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';

Future<void> confirmBlockChange(
  BuildContext context,
  String userId, {
  required bool blocked,
  String? name,
}) async {
  final cubit = context.read<BlockCubit>();
  if (cubit.state.pending.contains(userId)) return;
  final error = await cubit.checkStatus(userId);
  if (!context.mounted) return;
  if (error != null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.message)));
    return;
  }
  if (cubit.state.pending.contains(userId) ||
      cubit.state.isBlocked(userId) == blocked) {
    return;
  }
  final action = blocked ? 'Block' : 'Unblock';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('$action user?'),
      content: Text(
        blocked
            ? 'Block ${name ?? 'this user'}? Existing follows will remain.'
            : 'Unblock ${name ?? 'this user'}? Existing follow relationships will remain.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(action),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final result = await cubit.setBlocked(userId, blocked);
  if (!context.mounted) return;
  if (result != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        action: SnackBarAction(
          label: 'Retry',
          onPressed: () =>
              confirmBlockChange(context, userId, blocked: blocked, name: name),
        ),
      ),
    );
  }
}

class BlockUserButton extends StatelessWidget {
  const BlockUserButton({
    super.key,
    required this.userId,
    this.initialBlocked = false,
    this.name,
  });
  final String userId;
  final bool initialBlocked;
  final String? name;

  @override
  Widget build(BuildContext context) => BlocBuilder<BlockCubit, BlockState>(
    builder: (context, state) {
      final blocked = state.isBlocked(userId, fallback: initialBlocked);
      final pending = state.pending.contains(userId);
      return TextButton(
        onPressed: pending
            ? null
            : () => confirmBlockChange(
                context,
                userId,
                blocked: !blocked,
                name: name,
              ),
        child: Text(
          pending
              ? 'Updating…'
              : blocked
              ? 'Unblock'
              : 'Block',
        ),
      );
    },
  );
}
