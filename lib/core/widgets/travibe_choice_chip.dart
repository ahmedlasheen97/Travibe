import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';

/// Shared selection chip (Figma, Profile Setup step 2): dark fill, thin grey
/// border, white text; orange fill and border when selected. Used by Profile
/// Setup, Edit Profile and Buddies filters so every chip matches.
class TravibeChoiceChip extends StatelessWidget {
  const TravibeChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
  });
  final String label;
  final bool selected;

  /// Null makes the chip read-only (e.g. Edit Profile summaries).
  final VoidCallback? onTap;

  static const fill = Color(0xFF141414);
  static const border = Color(0xFF2A2A2A);

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    selected: selected,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? DarkColors.primaryColor : fill,
          border: Border.all(
            color: selected ? DarkColors.primaryColor : border,
          ),
          borderRadius: BorderRadius.circular(50),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            height: 20 / 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    ),
  );
}
