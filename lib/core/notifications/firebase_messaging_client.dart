import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'firebase_bootstrap.dart';
import 'push_message.dart';

enum PushPermission { unknown, notDetermined, denied, authorized, provisional }

abstract interface class MessagingClient {
  String get platform;
  bool get requiresApns;
  Future<bool> initialize();
  Future<PushPermission> permission();
  Future<PushPermission> requestPermission();
  Future<String?> apnsToken();
  Future<String?> token();
  Future<void> deleteToken();
  Future<PushMessage?> initialMessage();
  Stream<String> get tokenRefresh;
  Stream<PushMessage> get foreground;
  Stream<PushMessage> get opened;
}

/// No UI, navigation, authenticated requests, logs or payload persistence here.
/// The OS presents notification payloads in the background. Data-only messages
/// have no verified application work contract; authoritative data reloads on UI.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await FirebaseBootstrap.instance.initialize();
}

class FirebaseMessagingClient implements MessagingClient {
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  @override
  String get platform => defaultTargetPlatform.name;
  @override
  bool get requiresApns =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Future<bool> initialize() async {
    if (!await FirebaseBootstrap.instance.initialize()) return false;
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    // One in-app foreground signal, not simultaneous native/local banners.
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );
    return true;
  }

  static PushPermission permissionFromStatus(AuthorizationStatus status) =>
      switch (status) {
        AuthorizationStatus.authorized => PushPermission.authorized,
        AuthorizationStatus.provisional => PushPermission.provisional,
        AuthorizationStatus.denied => PushPermission.denied,
        AuthorizationStatus.deniedPermanently => PushPermission.denied,
        AuthorizationStatus.notDetermined => PushPermission.notDetermined,
      };

  @override
  Future<PushPermission> permission() async => permissionFromStatus(
    (await _messaging.getNotificationSettings()).authorizationStatus,
  );
  @override
  Future<PushPermission> requestPermission() async => permissionFromStatus(
    (await _messaging.requestPermission()).authorizationStatus,
  );
  @override
  Future<String?> apnsToken() => _messaging.getAPNSToken();
  @override
  Future<String?> token() => _messaging.getToken();
  @override
  Future<void> deleteToken() => _messaging.deleteToken();
  @override
  Future<PushMessage?> initialMessage() async {
    final message = await _messaging.getInitialMessage();
    return message == null ? null : PushMessage.fromRemote(message);
  }

  @override
  Stream<String> get tokenRefresh => _messaging.onTokenRefresh;
  @override
  Stream<PushMessage> get foreground =>
      FirebaseMessaging.onMessage.map(PushMessage.fromRemote);
  @override
  Stream<PushMessage> get opened =>
      FirebaseMessaging.onMessageOpenedApp.map(PushMessage.fromRemote);
}
