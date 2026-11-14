import 'package:travibe/core/constants/app_sizes.dart';
import 'package:flutter/material.dart';

class ProfileSavedSubTabs extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;

  const ProfileSavedSubTabs({
    super.key,
    required this.selectedIndex,
    required this.onTabSelected,
  });

  static const _labels = ['Posts', 'Hotels'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSizes.pw20,
        vertical: AppSizes.ph8,
      ),
      child: Row(
        children: [
          for (int i = 0; i < _labels.length; i++) ...[
            _tabItem(_labels[i], i),
            if (i != _labels.length - 1) SizedBox(width: AppSizes.w20),
          ],
        ],
      ),
    );
  }

  Widget _tabItem(String title, int index) {
    final isSelected = selectedIndex == index;
    return InkWell(
      onTap: () => onTabSelected(index),
      child: Text(
        title,
        style: TextStyle(
          fontSize: AppSizes.sp14,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
          color: isSelected ? Colors.white : Colors.white38,
        ),
      ),
    );
  }
}
