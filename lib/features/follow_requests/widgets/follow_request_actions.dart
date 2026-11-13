import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/follow_requests/cubit/incoming_requests_cubit.dart';

/// Orange "Accept" pill plus decline (an X, or a "decline" pill on the
/// profile card). Both resolve through [IncomingRequestsCubit], so every
/// surface showing this request updates together.
class FollowRequestActions extends StatelessWidget {
  const FollowRequestActions({
    super.key,
    required this.userId,
    this.declineAsPill = false,
    this.onAccepted,
  });
  final String userId;

  /// Profile card style: "decline" pill instead of an X icon.
  final bool declineAsPill;
  final VoidCallback? onAccepted;

  static final _pillShape = const StadiumBorder();

  Future<void> _run(BuildContext context, {required bool accept}) async {
    final cubit = context.read<IncomingRequestsCubit>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final error = accept
        ? await cubit.accept(userId)
        : await cubit.decline(userId);
    if (error != null) {
      messenger?.showSnackBar(SnackBar(content: Text(error.message)));
    } else if (accept) {
      onAccepted?.call();
    }
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<IncomingRequestsCubit, IncomingRequestsState>(
        buildWhen: (a, b) =>
            a.pending.contains(userId) != b.pending.contains(userId),
        builder: (context, state) {
          final busy = state.pending.contains(userId);
          final label = TextStyle(
            fontSize: AppSizes.sp14,
            fontWeight: FontWeight.w500,
            color: DarkColors.whiteColor,
          );
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(
                key: ValueKey('accept-request-$userId'),
                onPressed: busy ? null : () => _run(context, accept: true),
                style: FilledButton.styleFrom(
                  backgroundColor: DarkColors.primaryColor,
                  disabledBackgroundColor: DarkColors.primaryColor.withValues(
                    alpha: .5,
                  ),
                  minimumSize: Size(0, AppSizes.h32),
                  padding: EdgeInsets.symmetric(horizontal: AppSizes.w14),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: _pillShape,
                ),
                child: Text('Accept', style: label),
              ),
              SizedBox(width: declineAsPill ? AppSizes.w8 : AppSizes.w4),
              if (declineAsPill)
                FilledButton(
                  key: ValueKey('decline-request-$userId'),
                  onPressed: busy ? null : () => _run(context, accept: false),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2F2E2D),
                    disabledBackgroundColor: const Color(0xFF2F2E2D),
                    minimumSize: Size(0, AppSizes.h32),
                    padding: EdgeInsets.symmetric(horizontal: AppSizes.w14),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: _pillShape,
                  ),
                  child: Text('decline', style: label),
                )
              else
                IconButton(
                  key: ValueKey('decline-request-$userId'),
                  tooltip: 'Decline',
                  onPressed: busy ? null : () => _run(context, accept: false),
                  icon: const Icon(Icons.close, color: DarkColors.whiteColor),
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                  padding: EdgeInsets.zero,
                ),
            ],
          );
        },
      );
}
