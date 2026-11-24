import 'package:flutter/material.dart';
import 'package:travibe/core/widgets/display_sized_image.dart';

/// Uses the existing people-list fallback, including when a remote image fails.
class HomeUserAvatar extends StatelessWidget {
  const HomeUserAvatar({super.key, this.url, this.size = 56});
  final String? url;
  final double size;

  static const _placeholder = Color(0xFF2A2A2A);

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: _placeholder,
      child: Icon(Icons.person_rounded, color: Colors.white54, size: size / 2),
    );
    return ExcludeSemantics(
      child: ClipOval(
        child: SizedBox.square(
          dimension: size,
          child: url == null || url!.isEmpty
              ? fallback
              : Image(
                  image: DisplaySizedImage.of(
                    context,
                    NetworkImage(url!),
                    logicalWidth: size,
                    logicalHeight: size,
                  ),
                  fit: BoxFit.cover,
                  // A grey disc until the first frame, never an empty hole.
                  frameBuilder: (_, image, frame, sync) => sync || frame != null
                      ? image
                      : const ColoredBox(color: _placeholder),
                  errorBuilder: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }
}
