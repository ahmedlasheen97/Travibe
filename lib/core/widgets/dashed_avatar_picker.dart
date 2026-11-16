import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';

/// The profile picture picker shared by Profile Setup step 1 and Edit Profile:
/// a dashed orange circle with an orange "+" badge, [size] across.
class DashedAvatarPicker extends StatelessWidget {
  const DashedAvatarPicker({
    super.key,
    this.image,
    this.onTap,
    this.onImageError,
    this.avatarKey,
    this.badgeKey,
    this.semanticsLabel,
  });

  /// Outer diameter, ring included. Fixed so the circle keeps its geometry.
  static const double size = 128;
  static const double _ringPadding = 6;
  static const double _badge = 32;
  static const double _badgeInset = 4;

  final ImageProvider? image;

  /// Null disables the picker (e.g. while a pick or upload is in progress).
  final VoidCallback? onTap;
  final ImageErrorListener? onImageError;
  final Key? avatarKey, badgeKey;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      key: badgeKey,
      width: _badge,
      height: _badge,
      decoration: BoxDecoration(
        color: DarkColors.primaryColor,
        shape: BoxShape.circle,
        border: Border.all(color: DarkColors.backgroundColor, width: 3),
      ),
      child: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
    );
    return Semantics(
      label: semanticsLabel,
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            children: [
              DottedBorder(
                options: CircularDottedBorderOptions(
                  color: DarkColors.primaryColor,
                  strokeWidth: 1.5,
                  dashPattern: [
                    AppSizes.adaptiveRadius(18),
                    AppSizes.adaptiveRadius(12),
                  ],
                  padding: const EdgeInsets.all(_ringPadding),
                ),
                child: CircleAvatar(
                  key: avatarKey,
                  radius: size / 2 - _ringPadding,
                  backgroundColor: const Color(0xFFE0E0E0),
                  backgroundImage: image,
                  onBackgroundImageError: image == null ? null : onImageError,
                  child: image == null
                      ? const Icon(
                          Icons.person_rounded,
                          color: Colors.grey,
                          size: 48,
                        )
                      : null,
                ),
              ),
              PositionedDirectional(
                bottom: _badgeInset,
                end: _badgeInset,
                child: badge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
