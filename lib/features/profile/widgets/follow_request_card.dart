import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/follow_requests/cubit/incoming_requests_cubit.dart';
import 'package:travibe/features/follow_requests/widgets/follow_request_actions.dart';

/// "Requested to follow you." with Accept / decline (Figma profile card).
/// Renders nothing unless [userId] has a pending request to me.
class FollowRequestCard extends StatelessWidget {
  const FollowRequestCard({super.key, required this.userId, this.onAccepted});
  final String userId;
  final VoidCallback? onAccepted;

  @override
  Widget build(BuildContext context) {
    if (context.read<IncomingRequestsCubit?>() == null) {
      return const SizedBox.shrink();
    }
    return BlocBuilder<IncomingRequestsCubit, IncomingRequestsState>(
      buildWhen: (a, b) => a.contains(userId) != b.contains(userId),
      builder: (context, state) {
        if (!state.contains(userId)) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.fromLTRB(
            AppSizes.pw20,
            0,
            AppSizes.pw20,
            AppSizes.h16,
          ),
          child: Container(
            key: const ValueKey('follow-request-card'),
            padding: EdgeInsets.symmetric(
              horizontal: AppSizes.pw14,
              vertical: AppSizes.ph14,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(AppSizes.r20),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Requested to follow you.',
                    style: TextStyle(
                      color: DarkColors.whiteColor,
                      fontSize: AppSizes.sp14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(width: AppSizes.w8),
                FollowRequestActions(
                  userId: userId,
                  declineAsPill: true,
                  onAccepted: onAccepted,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
