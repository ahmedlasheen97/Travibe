import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';

/// Circular-bordered ⋮ button used on post cards and profiles.
class MoreOptionsButton extends StatelessWidget {
  const MoreOptionsButton({
    super.key,
    required this.onTap,
    required this.size,
    this.height,
    required this.radius,
    this.tooltip,
  });

  final VoidCallback? onTap;
  final double size;

  /// Defaults to [size].
  final double? height;
  final double radius;
  final String? tooltip;

  static const borderColor = Color(0xFF2E2E2E);

  @override
  Widget build(BuildContext context) {
    final button = InkWell(
      onTap: onTap,
      child: Container(
        width: size,
        height: height ?? size,
        decoration: BoxDecoration(
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: const Center(
          child: Icon(Icons.more_vert, color: DarkColors.whiteColor),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}
