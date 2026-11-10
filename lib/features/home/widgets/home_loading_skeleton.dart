import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:travibe/core/constants/app_sizes.dart';

/// Presentation-only bones: no placeholder posts enter the repository/cache.
class HomeFeedSkeleton extends StatelessWidget {
  const HomeFeedSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading posts',
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        AppSizes.adaptiveWidth(10),
        AppSizes.adaptiveHeight(16),
        AppSizes.adaptiveWidth(10),
        AppSizes.adaptiveHeight(16),
      ),
      child: Column(
        children: [
          for (var index = 0; index < 2; index++) ...[
            const _PostSkeleton(),
            SizedBox(height: AppSizes.adaptiveHeight(16)),
          ],
        ],
      ),
    ),
  );
}

class HomeStorySkeleton extends StatelessWidget {
  const HomeStorySkeleton({
    super.key,
    required this.avatarDiameter,
    required this.ringDiameter,
    required this.labelStyle,
  });
  final double avatarDiameter, ringDiameter;
  final TextStyle labelStyle;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: ringDiameter + AppSizes.adaptiveWidth(8),
    child: _SkeletonAnimation(
      child: Column(
        children: [
          Container(
            key: const ValueKey('story-skeleton-ring'),
            width: ringDiameter,
            height: ringDiameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF292929), width: 2),
            ),
            child: Center(
              child: _Bone(
                key: const ValueKey('story-skeleton-avatar'),
                width: avatarDiameter,
                height: avatarDiameter,
                radius: avatarDiameter / 2,
              ),
            ),
          ),
          SizedBox(height: AppSizes.adaptiveHeight(6)),
          // Measure the same line box as the real story name, including scaling.
          SizedBox(
            width: AppSizes.adaptiveWidth(48),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Opacity(opacity: 0, child: Text(' ', style: labelStyle)),
                _Bone(height: AppSizes.adaptiveHeight(8)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _SkeletonAnimation extends StatelessWidget {
  const _SkeletonAnimation({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: Shimmer.fromColors(
        enabled: !MediaQuery.disableAnimationsOf(context),
        period: const Duration(milliseconds: 1800),
        baseColor: const Color(0xFF232323),
        highlightColor: const Color(0xFF303030),
        child: child,
      ),
    ),
  );
}

class _PostSkeleton extends StatelessWidget {
  const _PostSkeleton();

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(AppSizes.adaptiveWidth(16)),
    decoration: BoxDecoration(
      color: const Color(0xFF141414),
      borderRadius: BorderRadius.circular(AppSizes.adaptiveRadius(20)),
    ),
    child: _SkeletonAnimation(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Bone(
                key: const ValueKey('post-skeleton-avatar'),
                width: AppSizes.adaptiveRadius(40),
                height: AppSizes.adaptiveRadius(40),
                radius: AppSizes.adaptiveRadius(20),
              ),
              SizedBox(width: AppSizes.adaptiveWidth(10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FractionallySizedBox(
                      widthFactor: .65,
                      child: _Bone(
                        key: ValueKey('post-skeleton-author'),
                        height: 14,
                      ),
                    ),
                    SizedBox(height: AppSizes.adaptiveHeight(6)),
                    const FractionallySizedBox(
                      widthFactor: .3,
                      child: _Bone(
                        key: ValueKey('post-skeleton-timestamp'),
                        height: 10,
                      ),
                    ),
                  ],
                ),
              ),
              _Bone(
                width: AppSizes.adaptiveRadius(38),
                height: AppSizes.adaptiveRadius(38),
                radius: AppSizes.adaptiveRadius(20),
              ),
            ],
          ),
          SizedBox(height: AppSizes.adaptiveHeight(20)),
          _Bone(
            key: const ValueKey('post-skeleton-caption'),
            height: AppSizes.adaptiveHeight(12),
          ),
          SizedBox(height: AppSizes.adaptiveHeight(6)),
          FractionallySizedBox(
            widthFactor: .75,
            child: _Bone(height: AppSizes.adaptiveHeight(12)),
          ),
          SizedBox(height: AppSizes.adaptiveHeight(12)),
          _Bone(
            key: const ValueKey('post-skeleton-media'),
            height: AppSizes.adaptiveHeight(220),
            radius: AppSizes.adaptiveRadius(16),
          ),
          const SizedBox(height: 20),
          Row(
            key: const ValueKey('post-skeleton-actions'),
            children: [
              for (var index = 0; index < 3; index++) ...[
                Expanded(child: _Bone(height: AppSizes.adaptiveHeight(28))),
                SizedBox(width: AppSizes.adaptiveWidth(12)),
              ],
              _Bone(
                width: AppSizes.adaptiveRadius(24),
                height: AppSizes.adaptiveRadius(28),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _Bone extends StatelessWidget {
  const _Bone({super.key, this.width, required this.height, this.radius = 6});
  final double? width;
  final double height, radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width ?? double.infinity,
    height: height,
    decoration: BoxDecoration(
      color: const Color(0xFF232323),
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}
