import 'package:flutter/material.dart';

/// Uses the existing people-list fallback, including when a remote image fails.
class HomeUserAvatar extends StatelessWidget {
  const HomeUserAvatar({super.key, this.url, this.size = 56});
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: const Color(0xFF2A2A2A),
      child: Icon(Icons.person_rounded, color: Colors.white54, size: size / 2),
    );
    return ExcludeSemantics(
      child: ClipOval(
        child: SizedBox.square(
          dimension: size,
          child: url == null || url!.isEmpty
              ? fallback
              : Image.network(
                  url!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }
}
