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
          const _Bone(width: 128, height: 128, radius: 64),
          SizedBox(height: AppSizes.h16),
          const _Bone(width: 136, height: 22),
          const SizedBox(height: 2),
          const _Bone(width: 80, height: 16),
          const SizedBox(height: 8),
          const _Bone(width: 210, height: 22),
          const SizedBox(height: 2),
          const _Bone(width: 160, height: 22),
          SizedBox(height: AppSizes.h20),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: _Bone(height: 68, radius: 20),
          ),
          SizedBox(height: AppSizes.h20),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(child: _Bone(height: 44, radius: 20)),
                SizedBox(width: 12),
                Expanded(child: _Bone(height: 44, radius: 20)),
              ],
            ),
          ),
          SizedBox(height: AppSizes.h24),
          const _Bone(width: 220, height: 26),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 24, 20, 100),
            child: _PostBones(),
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
    this.radius = 6,
  });
  final double width;
  final double height;
  final double radius;
  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: DarkColors.darkgreyColor,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

class _PostBones extends StatelessWidget {
  const _PostBones();
  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          _Bone(width: 40, height: 40, radius: 20),
          SizedBox(width: 12),
          _Bone(width: 120, height: 16),
        ],
      ),
      SizedBox(height: 16),
      _Bone(height: 16),
      SizedBox(height: 8),
      _Bone(width: 180, height: 16),
      SizedBox(height: 16),
      _Bone(height: 180, radius: 20),
    ],
  );
}
