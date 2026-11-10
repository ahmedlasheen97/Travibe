import 'package:flutter/services.dart';

enum ChatMicrophonePermission {
  notDetermined,
  granted,
  denied,
  permanentlyDenied,
  restricted,
}

/// Application-owned native permission/add-only gallery bridge. No startup
/// permission prompts, photo-library reads, or extra plugin/SwiftPM dependency.
class ChatDeviceMedia {
  const ChatDeviceMedia();
  static const channel = MethodChannel('travibe/chat_media');
  Future<ChatMicrophonePermission> microphone({bool request = false}) async {
    final value = await channel.invokeMethod<String>(
      request ? 'requestMicrophone' : 'microphoneStatus',
    );
    return ChatMicrophonePermission.values.firstWhere(
      (p) => p.name == value,
      orElse: () => ChatMicrophonePermission.restricted,
    );
  }

  Future<void> openSettings() => channel.invokeMethod<void>('openSettings');
  Future<void> saveVideo(String path, String mime) =>
      channel.invokeMethod<void>('saveVideo', {'path': path, 'mime': mime});
  Future<void> saveImage(Uint8List bytes) =>
      channel.invokeMethod<void>('saveImage', {'bytes': bytes});
}
