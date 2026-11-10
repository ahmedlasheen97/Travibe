import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';

/// A small, clipped backdrop using the app's existing ten-pixel blur treatment.
/// Only the component bounds filter the photo behind it, never the full canvas.
class StoryGlass extends StatelessWidget {
  const StoryGlass({super.key, required this.child});
  final Widget child;
  static final _blur = ImageFilter.blur(sigmaX: 10, sigmaY: 10);
  static final _radius = BorderRadius.circular(999);

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: _radius,
    child: BackdropFilter(
      filter: _blur,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: DarkColors.darkgreyColor.withValues(alpha: .6),
          borderRadius: _radius,
          border: Border.all(color: Colors.white.withValues(alpha: .12)),
        ),
        child: child,
      ),
    ),
  );
}
