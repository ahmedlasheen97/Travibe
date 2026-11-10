import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

class CustomBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onItemSelected;

  const CustomBottomNav({
    required this.currentIndex,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(40),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 10,
          sigmaY: 10,
        ),
        child: Container(
          height: 78,

          decoration: BoxDecoration(
            color: const Color(0x801F1F1F), // #1F1F1F 50%
            borderRadius: BorderRadius.circular(40),

            border: Border.all(
              color: const Color(0x555F5F5F),
              width: 1,
            ),
          ),

          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                index: 0,
                currentIndex: currentIndex,
                icon: 'assets/images/home/home.svg',
                label: 'Home',
                onTap: onItemSelected,
              ),

              _NavItem(
                index: 1,
                currentIndex: currentIndex,
                icon: 'assets/images/home/Compas.svg',
                label: 'Explore',
                onTap: onItemSelected,
              ),

              _PlusButton(
                onTap: () => onItemSelected(2),
              ),

              _NavItem(
                index: 3,
                currentIndex: currentIndex,
                icon: 'assets/images/home/user.svg',
                label: 'Buddies',
                onTap: onItemSelected,
              ),

              _NavItem(
                index: 4,
                currentIndex: currentIndex,
                icon: 'assets/images/home/profile-2user.svg',
                label: 'Profile',
                onTap: onItemSelected,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
class _NavItem extends StatelessWidget {
  final int index;
  final int currentIndex;
  final String icon;
  final String label;
  final ValueChanged<int> onTap;

  const _NavItem({
    required this.index,
    required this.currentIndex,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool selected = index == currentIndex;

    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 65,
        height: 70,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              icon,
              width: 22,
              height: 22,

              colorFilter: ColorFilter.mode(
                selected
                    ? Colors.white
                    : const Color(0xFF9E9E9E),
                BlendMode.srcIn,
              ),
            ),

            const SizedBox(height: 5),

            Text(
              label,
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: selected
                    ? Colors.white
                    : const Color(0xFF9E9E9E),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
class _PlusButton extends StatelessWidget {
  final VoidCallback onTap;

  const _PlusButton({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SvgPicture.asset(
        'assets/images/home/Component 53 (1).svg',
        width: 58,
        height: 58,
      ),
    );
  }
}