import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';

class PinnedTabsDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  PinnedTabsDelegate({required this.child, required this.height});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: DarkColors.backgroundColor,
      alignment: Alignment.center,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant PinnedTabsDelegate oldDelegate) {
    return oldDelegate.child != child || oldDelegate.height != height;
  }
}