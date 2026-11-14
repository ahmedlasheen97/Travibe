import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';

/// Grey/white "Follows you" pill shared by profiles and people lists.
/// [compact] is the smaller list-row variant shown above a user's picture.
class FollowsYouBadge extends StatelessWidget {
  const FollowsYouBadge({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    key: const ValueKey('follows-you-badge'),
    decoration: BoxDecoration(
      color: DarkColors.darkgreyColor,
      borderRadius: BorderRadius.circular(compact ? AppSizes.r6 : AppSizes.r8),
    ),
    child: Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSizes.pw6 : AppSizes.pw10,
        vertical: compact ? AppSizes.ph2 : AppSizes.ph4,
      ),
      child: Text(
        'Follows you',
        style: TextStyle(
          color: DarkColors.whiteColor,
          fontSize: compact ? AppSizes.sp11 : AppSizes.sp12,
        ),
      ),
    ),
  );
}
