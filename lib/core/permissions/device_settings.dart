import 'package:flutter/services.dart';

/// Opens this app's page in the system Settings through the app-owned native
/// bridge (iOS `openSettingsURLString`, Android app details). No plugin needed.
class DeviceSettings {
  const DeviceSettings();
  static const channel = MethodChannel('travibe/chat_media');

  /// Returns false when Settings could not be opened.
  Future<bool> open() async {
    try {
      await channel.invokeMethod<void>('openSettings');
      return true;
    } catch (_) {
      return false;
    }
  }
}
