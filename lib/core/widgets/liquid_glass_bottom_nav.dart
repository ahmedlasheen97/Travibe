import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:travibe/core/theme/bottom_nav_style.dart';

/// Presentation only: the existing Material bar owns taps, labels and semantics.
/// Remains attached to Scaffold's reserved bottom area; no body/route changes.
class LiquidGlassBottomNav extends StatelessWidget {
  const LiquidGlassBottomNav({super.key, required this.navigation});
  final BottomNavigationBar navigation;
  static final _blur = ImageFilter.blur(sigmaX: 18, sigmaY: 18);

  /// Full bar height including the system bottom inset (theme `AppSizes.h95`,
  /// never less than 64px of controls above the inset).
  static double heightOf(BuildContext context) {
    final style = Theme.of(context).extension<BottomNavStyle>()!;
    final inset = MediaQuery.viewPaddingOf(context).bottom;
    return math.max(64.0, style.height - inset) + inset;
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).extension<BottomNavStyle>()!;
    final padding = MediaQuery.paddingOf(context);
    final radius = BorderRadius.vertical(
      top: Radius.circular(math.min(style.radius, 32)),
    );
    // Keep the theme height when possible, with >=64px controls above system UI.
    final minimumContentHeight = math.max(64.0, style.height - padding.bottom);
    return ClipRRect(
      key: const ValueKey('liquid-glass-navigation'),
      borderRadius: radius,
      child: BackdropFilter(
        filter: _blur,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: style.backgroundColor.withValues(alpha: .68),
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: .1),
                Colors.white.withValues(alpha: .025),
                Colors.black.withValues(alpha: .08),
              ],
            ),
          ),
          child: SafeArea(
            top: false,
            // SafeArea owns system insets; Material must not apply them again.
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minimumContentHeight),
              child: MediaQuery.removePadding(
                context: context,
                removeBottom: true,
                child: navigation,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
