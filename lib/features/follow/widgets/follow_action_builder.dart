import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/widgets/glass_confirm_dialog.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';

export 'package:travibe/features/follow/cubit/follow_cubit.dart'
    show FollowRelation;

extension FollowRelationLabel on FollowRelation {
  bool get isFollowing => this == FollowRelation.following;
  bool get isRequested => this == FollowRelation.requested;
  String get label => switch (this) {
    FollowRelation.follow => 'Follow',
    FollowRelation.following => 'Following',
    FollowRelation.requested => 'Requested',
  };
}

/// Grey label used for the "Requested" state on every follow button.
const requestedFollowColor = Color(0xFF989693);

/// Keeps every occurrence of a user in sync without mutating feed/search models.
///
/// Tapping "Requested" asks before cancelling the pending request.
class FollowActionBuilder extends StatelessWidget {
  const FollowActionBuilder({
    super.key,
    required this.userId,
    required this.initialFollowing,
    this.initialRequested = false,
    required this.builder,
  });
  final String userId;
  final bool initialFollowing;
  final bool initialRequested;
  final Widget Function(
    BuildContext,
    FollowRelation relation,
    bool pending,
    VoidCallback? onToggle,
  )
  builder;

  static Future<bool> confirmCancelRequest(BuildContext context) =>
      showGlassConfirmDialog(
        context,
        title: 'Cancel follow request?',
        message: 'You can request to follow this account again later.',
        confirmLabel: 'Cancel request',
        cancelLabel: 'Keep',
      );

  @override
  Widget build(BuildContext context) => BlocBuilder<FollowCubit, FollowState>(
    builder: (context, state) {
      final relation = state.relationOf(
        userId,
        initialFollowing: initialFollowing,
        initialRequested: initialRequested,
      );
      final pending = state.pending.contains(userId);
      final allowed = context.read<FollowCubit>().canInteract(userId);
      return builder(
        context,
        relation,
        pending,
        pending || !allowed
            ? null
            : () async {
                final cubit = context.read<FollowCubit>();
                if (relation == FollowRelation.requested &&
                    !await confirmCancelRequest(context)) {
                  return;
                }
                final error = await cubit.toggle(
                  userId,
                  currentlyFollowing: relation == FollowRelation.following,
                  currentlyRequested: relation == FollowRelation.requested,
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
