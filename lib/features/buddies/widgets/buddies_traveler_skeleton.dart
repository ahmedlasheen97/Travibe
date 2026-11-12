import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:travibe/core/constants/app_sizes.dart';

/// Placeholder geometry only: never sample travelers or synthetic data.
/// Mirrors [BuddiesTravelerCard]: photo, name, destination, dates, chips.
class BuddiesTravelerCardSkeleton extends StatelessWidget {
  const BuddiesTravelerCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final radius = AppSizes.adaptiveRadius(16);
    return Container(
      key: const ValueKey('buddies-skeleton-card'),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: _Shimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _Bone(
              height: AppSizes.adaptiveHeight(134),
              borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSizes.adaptiveWidth(8),
                AppSizes.adaptiveHeight(10),
                AppSizes.adaptiveWidth(8),
                AppSizes.adaptiveHeight(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FractionallySizedBox(
                    widthFactor: .7,
                    child: _Bone(height: AppSizes.adaptiveHeight(12)),
                  ),
                  SizedBox(height: AppSizes.adaptiveHeight(8)),
                  FractionallySizedBox(
                    widthFactor: .5,
                    child: _Bone(height: AppSizes.adaptiveHeight(10)),
                  ),
                  SizedBox(height: AppSizes.adaptiveHeight(8)),
                  FractionallySizedBox(
                    widthFactor: .4,
                    child: _Bone(height: AppSizes.adaptiveHeight(10)),
                  ),
                  SizedBox(height: AppSizes.adaptiveHeight(16)),
                  Row(
                    children: [
                      for (final width in const [56.0, 44.0]) ...[
                        _Bone(
                          width: AppSizes.adaptiveWidth(width),
                          height: AppSizes.adaptiveHeight(24),
                          borderRadius: BorderRadius.circular(
                            AppSizes.adaptiveRadius(24),
                          ),
                        ),
                        SizedBox(width: AppSizes.adaptiveWidth(4)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A Buddies landing section: header bone plus a horizontal card row sized
/// like [BuddiesTravelerSection].
class BuddiesSectionSkeleton extends StatelessWidget {
  const BuddiesSectionSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final side = AppSizes.adaptiveWidth(20);
    final gap = AppSizes.adaptiveWidth(16);
    return _Loading(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: side),
            child: _Shimmer(
              child: _Bone(
                width: AppSizes.adaptiveWidth(140),
                height: AppSizes.adaptiveHeight(16),
              ),
            ),
          ),
          SizedBox(height: AppSizes.adaptiveHeight(16)),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 2 * side)
                  .clamp(1, AppSizes.adaptiveWidth(167))
                  .toDouble();
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: side),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      if (i > 0) SizedBox(width: gap),
                      SizedBox(
                        width: width,
                        child: const BuddiesTravelerCardSkeleton(),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Two-column card grid matching the See All / search result rows.
class BuddiesGridSkeleton extends StatelessWidget {
  const BuddiesGridSkeleton({super.key, this.rows = 2});
  final int rows;

  @override
  Widget build(BuildContext context) {
    final gap = AppSizes.adaptiveWidth(16);
    return _Loading(
      child: Column(
        children: [
          for (var row = 0; row < rows; row++)
            Padding(
              padding: EdgeInsets.only(bottom: AppSizes.adaptiveHeight(16)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(child: BuddiesTravelerCardSkeleton()),
                  SizedBox(width: gap),
                  const Expanded(child: BuddiesTravelerCardSkeleton()),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading travelers',
    liveRegion: true,
    child: ExcludeSemantics(child: IgnorePointer(child: child)),
  );
}

class _Shimmer extends StatelessWidget {
  const _Shimmer({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
    enabled: !MediaQuery.disableAnimationsOf(context),
    period: const Duration(milliseconds: 1800),
    baseColor: const Color(0xFF232323),
    highlightColor: const Color(0xFF303030),
    child: child,
  );
}

class _Bone extends StatelessWidget {
  const _Bone({this.width, required this.height, this.borderRadius});
  final double? width;
  final double height;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) => Container(
    width: width ?? double.infinity,
    height: height,
    decoration: BoxDecoration(
      color: const Color(0xFF232323),
      borderRadius:
          borderRadius ?? BorderRadius.circular(AppSizes.adaptiveRadius(6)),
    ),
  );
}
