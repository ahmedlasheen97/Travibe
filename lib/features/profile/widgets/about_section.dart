import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';

class AboutSection extends StatelessWidget {
  final String title;
  final Widget child;

  const AboutSection({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
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
      spacing: 8,
      runSpacing: 8,
      children: items.map((item) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF8361DA).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            item,
            style: TextStyle(color: DarkColors.whiteColor, fontSize: 13),
          ),
        );
      }).toList(),
    );
  }
}
