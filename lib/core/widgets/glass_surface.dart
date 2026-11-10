import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';

/// The clipped, moderate blur treatment shared by Travibe dialogs and controls.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = 24,
    this.opacity = .78,
    this.surfaceKey,
  });
  final Widget child;
  final double radius, opacity;
  final Key? surfaceKey;
  static final _blur = ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8);

  @override
  Widget build(BuildContext context) {
    final opaque =
        MediaQuery.highContrastOf(context) ||
        MediaQuery.disableAnimationsOf(context);
    final surface = DecoratedBox(
      key: surfaceKey,
      decoration: BoxDecoration(
        color: DarkColors.darkgreyColor.withValues(alpha: opaque ? 1 : opacity),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: Colors.white.withValues(alpha: opaque ? .3 : .10),
        ),
      ),
      child: child,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: opaque ? surface : BackdropFilter(filter: _blur, child: surface),
    );
  }
}
