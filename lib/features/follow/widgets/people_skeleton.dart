import 'package:travibe/core/constants/app_sizes.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:travibe/core/theme/dark_colors.dart';

/// Shimmer rows shown while a people list loads.
class PeopleSkeleton extends StatelessWidget {
  const PeopleSkeleton({super.key});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Shimmer.fromColors(
      enabled: !MediaQuery.disableAnimationsOf(context),
      baseColor: DarkColors.darkgreyColor,
      highlightColor: DarkColors.greyColor.withValues(alpha: .25),
      child: Column(
        children: [
          for (var i = 0; i < 4; i++)
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSizes.pw20,
                AppSizes.ph14,
                AppSizes.pw20,
                0,
              ),
              child: Container(
                height: AppSizes.h76,
                decoration: BoxDecoration(
                  color: DarkColors.darkgreyColor,
                  borderRadius: BorderRadius.circular(AppSizes.r20),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
