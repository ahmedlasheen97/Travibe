import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/widgets/glass_surface.dart';

class BackButtonWidget extends StatelessWidget {
  const BackButtonWidget({
    super.key,
    this.onTap,
    this.size = 44,
    this.iconSize = 24,
    this.enabled = true,
  });
  final VoidCallback? onTap;
  final double size, iconSize;
  final bool enabled;

  @override
  Widget build(BuildContext context) => IconButton(
    iconSize: size,
    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
    onPressed: enabled ? onTap ?? () => Navigator.of(context).maybePop() : null,
    style: IconButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: Size.square(math.max(44, size)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: const CircleBorder(),
    ),
    icon: Opacity(
      opacity: enabled ? 1 : .4,
      child: GlassSurface(
        radius: 999,
        opacity: .65,
        child: SizedBox.square(
          dimension: size,
          child: Center(
            child: SvgPicture.asset(
              'assets/images/home/arrow-left.svg',
              width: iconSize,
              height: iconSize,
              matchTextDirection: true,
              colorFilter: const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
              excludeFromSemantics: true,
            ),
          ),
        ),
      ),
    ),
  );
}
