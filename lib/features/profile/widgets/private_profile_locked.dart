import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';

/// Replaces posts/About on a private account the viewer cannot see.
class PrivateProfileLocked extends StatelessWidget {
  const PrivateProfileLocked({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('private-profile-locked'),
    padding: EdgeInsets.fromLTRB(
      AppSizes.pw20,
      AppSizes.h32,
      AppSizes.pw20,
      AppSizes.h40,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The asset draws its own ring, so it replaces the bordered circle
        // at the same 72 size.
        SvgPicture.asset(
          'assets/images/icons/lock-circle.svg',
          key: const ValueKey('private-profile-lock'),
          width: AppSizes.w72,
          height: AppSizes.w72,
          colorFilter: const ColorFilter.mode(
            DarkColors.whiteColor,
            BlendMode.srcIn,
          ),
          excludeFromSemantics: true,
        ),
        SizedBox(height: AppSizes.h16),
        Text(
          'This account is private',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: DarkColors.whiteColor,
            fontSize: AppSizes.sp17,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: AppSizes.h8),
        Text(
          'Follow this account to see their posts',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: DarkColors.greyColor,
            fontSize: AppSizes.sp14,
          ),
        ),
      ],
    ),
  );
}
