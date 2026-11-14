import 'package:travibe/core/constants/app_sizes.dart';
import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';

class AboutSection extends StatelessWidget {
  final String title;
  final Widget child;

  const AboutSection({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppSizes.ph20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.white,
              fontSize: AppSizes.sp15,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: AppSizes.h8),
          child,
        ],
      ),
    );
  }
}

class ChipsRow extends StatelessWidget {
  final List<String> items;

  const ChipsRow({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSizes.w8,
      runSpacing: AppSizes.h8,
      children: items.map((item) {
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: AppSizes.pw14,
            vertical: AppSizes.ph8,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF8361DA).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppSizes.r20),
          ),
          child: Text(
            item,
            style: TextStyle(
              color: DarkColors.whiteColor,
              fontSize: AppSizes.sp13,
            ),
          ),
        );
      }).toList(),
    );
  }
}
