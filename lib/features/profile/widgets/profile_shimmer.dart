import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';

/// Uses the installed skeleton animation package; one clock for the whole body.
class ProfileShimmer extends StatelessWidget {
  const ProfileShimmer({super.key});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    physics: const NeverScrollableScrollPhysics(),
    child: _ProfileSkeletonAnimation(
      child: Column(
        children: [
          SizedBox(height: AppSizes.h20),
          _Bone(
            width: AppSizes.w128,
            height: AppSizes.h128,
            radius: AppSizes.r64,
          ),
          SizedBox(height: AppSizes.h16),
          _Bone(width: AppSizes.w136, height: AppSizes.h22),
          SizedBox(height: AppSizes.h2),
          _Bone(width: AppSizes.w80, height: AppSizes.h16),
          SizedBox(height: AppSizes.h8),
          _Bone(width: AppSizes.w210, height: AppSizes.h22),
          SizedBox(height: AppSizes.h2),
          _Bone(width: AppSizes.w160, height: AppSizes.h22),
          SizedBox(height: AppSizes.h20),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSizes.pw20),
            child: _Bone(height: AppSizes.h68, radius: AppSizes.r20),
          ),
          SizedBox(height: AppSizes.h20),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSizes.pw20),
            child: Row(
              children: [
                Expanded(
                  child: _Bone(height: AppSizes.h44, radius: AppSizes.r20),
                ),
                SizedBox(width: AppSizes.w12),
                Expanded(
                  child: _Bone(height: AppSizes.h44, radius: AppSizes.r20),
                ),
              ],
            ),
          ),
          SizedBox(height: AppSizes.h24),
          _Bone(width: AppSizes.w220, height: AppSizes.h26),
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSizes.pw20,
              AppSizes.ph24,
              AppSizes.pw20,
              AppSizes.ph100,
            ),
            child: const _PostBones(),
          ),
        ],
      ),
    ),
  );
}

/// The profile resource may arrive before its independent author-post request.
class ProfilePostSkeleton extends StatelessWidget {
  const ProfilePostSkeleton({super.key});
  @override
  Widget build(BuildContext context) =>
      const _ProfileSkeletonAnimation(child: _PostBones());
}

class _ProfileSkeletonAnimation extends StatelessWidget {
  const _ProfileSkeletonAnimation({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: Shimmer.fromColors(
        enabled: !MediaQuery.disableAnimationsOf(context),
        baseColor: DarkColors.darkgreyColor,
        highlightColor: DarkColors.greyColor.withValues(alpha: .28),
        child: child,
      ),
    ),
  );
}

class _Bone extends StatelessWidget {
  const _Bone({
    this.width = double.infinity,
    required this.height,
    this.radius,
  });
  final double width;
  final double height;
  final double? radius;
  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: DarkColors.darkgreyColor,
      borderRadius: BorderRadius.circular(radius ?? AppSizes.r6),
    ),
  );
}

class _PostBones extends StatelessWidget {
  const _PostBones();
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          _Bone(
            width: AppSizes.w40,
            height: AppSizes.h40,
            radius: AppSizes.r20,
          ),
          SizedBox(width: AppSizes.w12),
          _Bone(width: AppSizes.w120, height: AppSizes.h16),
        ],
      ),
      SizedBox(height: AppSizes.h16),
      _Bone(height: AppSizes.h16),
      SizedBox(height: AppSizes.h8),
      _Bone(width: AppSizes.w180, height: AppSizes.h16),
      SizedBox(height: AppSizes.h16),
      _Bone(height: AppSizes.h180, radius: AppSizes.r20),
    ],
  );
}
