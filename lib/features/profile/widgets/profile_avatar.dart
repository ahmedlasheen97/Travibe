import 'package:flutter/material.dart';

class ProfileAvatar extends StatelessWidget {
  final String? imageUrl;

  const ProfileAvatar({super.key, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    final hasImage = url != null && url.isNotEmpty;

    return CircleAvatar(
      radius: 64,
      backgroundColor: const Color(0xFF2A2A2A),
      backgroundImage: hasImage ? NetworkImage(url) : null,
      child: hasImage
          ? null
          : const Icon(Icons.person_rounded, color: Colors.white54, size: 56),
    );
  }
}
