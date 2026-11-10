import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/constants/app_sizes.dart';

class HomeTabs extends StatelessWidget {
  const HomeTabs({
    super.key,
    required this.selectedIndex,
    required this.onTabSelected,
    required this.onSearchTap,
  });
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onSearchTap;
  static const _labels = ['For You', 'Following'];
  static double get _dot => AppSizes.adaptiveRadius(6);
  static double get _indicatorSpace => AppSizes.adaptiveHeight(6) + _dot;
  static Size _measureLabel(
    BuildContext context,
    String label, {
    bool selected = true,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: DefaultTextStyle.of(context).style.merge(
          TextStyle(
            fontFamily: 'Plus Jakarta Sans',
            fontSize: AppSizes.adaptiveFont(15),
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final size = painter.size;
    painter.dispose();
    return size;
  }

  static double preferredHeight(BuildContext context) => math.max(
    48.0,
    _measureLabel(context, _labels[1]).height + _indicatorSpace,
  );

  @override
  Widget build(BuildContext context) => SizedBox(
    height: preferredHeight(context),
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSizes.adaptiveWidth(20)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final first =
              _measureLabel(
                context,
                _labels[0],
                selected: selectedIndex == 0,
              ).width +
              1;
          final second =
              _measureLabel(
                context,
                _labels[1],
                selected: selectedIndex == 1,
              ).width +
              1;
          // Reserve the Search touch target symmetrically. This keeps the group
          // centered on Home itself rather than on the space preceding Search.
          final available = math.max(
            0.0,
            constraints.maxWidth - 2 * (44 + AppSizes.adaptiveWidth(4)),
          );
          final gap = math.min(AppSizes.adaptiveWidth(16), available);
          final ratio = math.min(1.0, (available - gap) / (first + second));
          return Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: SizedBox(
                  key: const ValueKey('home-feed-tab-group'),
                  width: (first + second) * ratio + gap,
                  height: preferredHeight(context),
                  child: Row(
                    children: [
                      SizedBox(
                        width: first * ratio,
                        child: _tabItem(_labels[0], 0),
                      ),
                      SizedBox(
                        key: const ValueKey('home-feed-tab-gap'),
                        width: gap,
                      ),
                      SizedBox(
                        width: second * ratio,
                        child: _tabItem(_labels[1], 1),
                      ),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 44,
                  height: preferredHeight(context),
                  child: IconButton(
                    key: const ValueKey('home-search'),
                    tooltip: 'Search',
                    onPressed: onSearchTap,
                    padding: EdgeInsets.zero,
                    icon: Transform.translate(
                      offset: Offset(0, -_indicatorSpace / 2),
                      child: SvgPicture.asset(
                        'assets/images/interactions/search-normal.svg',
                        key: const ValueKey('home-search-icon'),
                        width: 20,
                        height: 20,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _tabItem(String title, int index) {
    final selected = selectedIndex == index;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: () => onTabSelected(index),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: AppSizes.adaptiveFont(15),
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: selected ? Colors.white : Colors.white54,
                  ),
                ),
              ),
            ),
            SizedBox(
              height: _indicatorSpace,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: selected
                    ? Container(
                        key: ValueKey('home-tab-indicator-$index'),
                        width: _dot,
                        height: _dot,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
