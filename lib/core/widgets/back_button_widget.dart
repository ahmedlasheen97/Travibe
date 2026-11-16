import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/widgets/glass_surface.dart';

class BackButtonWidget extends StatelessWidget {
  const BackButtonWidget({super.key, this.onTap, this.enabled = true})
    : close = false;

  /// Same glass circle with an X, for full-screen viewers.
  const BackButtonWidget.close({super.key, this.onTap, this.enabled = true})
    : close = true;

  /// The one app-wide back button: always a 44×44 glass circle, 24 icon.
  static const double size = 44, iconSize = 24;

  final VoidCallback? onTap;
  final bool enabled;
  final bool close;

  @override
  Widget build(BuildContext context) => IconButton(
    iconSize: size,
    tooltip: close
        ? MaterialLocalizations.of(context).closeButtonTooltip
        : MaterialLocalizations.of(context).backButtonTooltip,
    onPressed: enabled ? onTap ?? () => Navigator.of(context).maybePop() : null,
    style: IconButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: const Size.square(size),
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
            child: close
                ? const Icon(Icons.close, size: iconSize, color: Colors.white)
                : SvgPicture.asset(
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
