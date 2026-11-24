import 'package:flutter/material.dart';
import 'package:travibe/core/widgets/display_sized_image.dart';

/// Uses the existing people-list fallback, including when a remote image fails.
class HomeUserAvatar extends StatelessWidget {
  const HomeUserAvatar({
    super.key,
    this.url,
    this.size = 56,
    this.height,
    this.borderRadius,
  });
  final String? url;

  /// Width; also the height unless [height] is set.
  final double size;
  final double? height;

  /// Null clips to a circle; otherwise a rounded rectangle.
  final double? borderRadius;

  static const _placeholder = Color(0xFF2A2A2A);

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: _placeholder,
      child: Icon(Icons.person_rounded, color: Colors.white54, size: size / 2),
    );
    final h = height ?? size;
    final box = SizedBox(
      width: size,
      height: h,
      child: url == null || url!.isEmpty
          ? fallback
          : Image(
              image: DisplaySizedImage.of(
                context,
                NetworkImage(url!),
                logicalWidth: size,
                logicalHeight: h,
              ),
              fit: BoxFit.cover,
              // A grey disc until the first frame, never an empty hole.
              frameBuilder: (_, image, frame, sync) => sync || frame != null
                  ? image
                  : const ColoredBox(color: _placeholder),
              errorBuilder: (_, _, _) => fallback,
            ),
    );
    return ExcludeSemantics(
      child: borderRadius == null
          ? ClipOval(child: box)
          : ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius!),
              child: box,
            ),
    );
  }
}
