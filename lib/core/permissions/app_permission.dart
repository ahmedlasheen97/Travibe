import 'package:flutter/material.dart';

/// Device permissions Travibe asks for, each with the copy shown by the shared
/// "Open Settings" sheet once the system prompt can no longer be shown.
enum AppPermission {
  notifications(
    Icons.notifications_rounded,
    'Notifications are off',
    'Turn on notifications in Settings to know when someone follows you, '
        'likes your posts or sends you a message.',
  ),
  photos(
    Icons.photo_library_rounded,
    'Allow photo access',
    'Travibe needs access to your photos so you can add pictures to your '
        'posts, stories, profile and chats. You can turn it on in Settings.',
  ),
  photosAdd(
    Icons.download_rounded,
    'Allow saving to Photos',
    'Travibe needs permission to add photos so it can save media from your '
        'conversations. You can turn it on in Settings.',
  ),
  camera(
    Icons.photo_camera_rounded,
    'Allow camera access',
    'Travibe needs your camera to take photos for your posts, stories and '
        'chats. You can turn it on in Settings.',
  ),
  microphone(
    Icons.mic_rounded,
    'Allow microphone access',
    'Travibe needs your microphone to record voice messages. You can turn it '
        'on in Settings.',
  );

  const AppPermission(this.icon, this.title, this.message);
  final IconData icon;
  final String title, message;
}
