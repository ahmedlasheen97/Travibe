import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/widgets/top_glow_background.dart';

class PinnedTabsDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  PinnedTabsDelegate({required this.child, required this.height});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // Shows the page color + fixed top glow behind the tabs (no solid band),
    // still hiding posts under it; they fade out below once it is pinned.
    return TopGlowBackdrop(
      key: const ValueKey('home-tabs-backdrop'),
      fadeExtent: AppSizes.adaptiveHeight(24),
      fadeWhenPinned: true,
      child: Align(child: child),
    );
  }

  @override
  bool shouldRebuild(covariant PinnedTabsDelegate oldDelegate) {
    return oldDelegate.child != child || oldDelegate.height != height;
  }
}
