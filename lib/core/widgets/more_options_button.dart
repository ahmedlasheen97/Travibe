import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/glass_surface.dart';

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

/// App-bar ⋮ button matching [BackButtonWidget]: 44×44 glass circle.
class AppBarMoreButton extends StatelessWidget {
  const AppBarMoreButton({
    super.key,
    required this.onTap,
    this.tooltip = 'More options',
    this.size = 44,
    this.iconSize = 24,
  });
  final VoidCallback? onTap;
  final String tooltip;
  final double size, iconSize;

  @override
  Widget build(BuildContext context) => IconButton(
    iconSize: size,
    tooltip: tooltip,
    onPressed: onTap,
    style: IconButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: Size.square(math.max(44, size)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: const CircleBorder(),
    ),
    icon: GlassSurface(
      radius: 999,
      opacity: .65,
      child: SizedBox.square(
        dimension: size,
        child: Icon(
          Icons.more_vert,
          size: iconSize,
          color: DarkColors.whiteColor,
        ),
      ),
    ),
  );
}
