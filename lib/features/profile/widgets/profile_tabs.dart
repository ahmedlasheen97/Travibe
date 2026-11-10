import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';

class ProfileTabs extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final bool showSaved;

  const ProfileTabs({
    super.key,
    required this.selectedIndex,
    required this.onTabSelected,
    this.showSaved = true,
  });

  static const _labels = ['Posts', 'About', 'Saved'];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < (showSaved ? _labels.length : 2); i++) ...[
          _tabItem(_labels[i], i),
          if (i != (showSaved ? _labels.length : 2) - 1)
            SizedBox(width: AppSizes.w24),
        ],
      ],
    );
  }

  Widget _tabItem(String title, int index) {
    final isSelected = selectedIndex == index;
    return InkWell(
      onTap: () => onTabSelected(index),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
              color: isSelected ? Colors.white : Colors.white54,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 2,
            color: isSelected ? Colors.white : Colors.transparent,
          ),
        ],
      ),
    );
  }
}
