import 'dart:async';
import 'package:travibe/core/notifications/firebase_messaging_client.dart';
import 'package:travibe/core/notifications/push_message.dart';
import 'package:travibe/features/notifications/data/push_token_repository.dart';

class FakeMessagingClient implements MessagingClient {
  PushPermission status = PushPermission.authorized;
  bool available = true;
  @override
  bool requiresApns = true;
  String? apns = 'apns', currentToken = 'device-a';
  PushMessage? initial;
  Object? tokenFailure;
  Completer<String?>? tokenGate;
  Completer<PushPermission>? permissionGate;
  int starts = 0, reads = 0, deletes = 0, prompts = 0, apnsReads = 0;
  final tokens = StreamController<String>.broadcast();
  final messages = StreamController<PushMessage>.broadcast();
  final taps = StreamController<PushMessage>.broadcast();
  @override
  String get platform => 'iOS';
  @override
  Future<bool> initialize() async {
    starts++;
    return available;
  }

  @override
  Future<PushPermission> permission() async => status;
  @override
  Future<PushPermission> requestPermission() async {
    prompts++;
    return permissionGate == null ? status : permissionGate!.future;
  }

  @override
  Future<String?> apnsToken() async {
    apnsReads++;
    return apns;
  }

  @override
  Future<String?> token() async {
    reads++;
    if (tokenFailure != null) throw tokenFailure!;
    return tokenGate == null ? currentToken : tokenGate!.future;
  }

  @override
  Future<void> deleteToken() async {
    deletes++;
  }

  @override
  Future<PushMessage?> initialMessage() async => initial;
  @override
  Stream<String> get tokenRefresh => tokens.stream;
  @override
  Stream<PushMessage> get foreground => messages.stream;
  @override
  Stream<PushMessage> get opened => taps.stream;
  Future<void> close() async {
    await tokens.close();
    await messages.close();
    await taps.close();
  }
}

class FakePushRepository implements PushTokenRepository {
  @override
  bool supported = true;
  final registered = <PushRegistration>[], revoked = <PushRegistration>[];
  final events = <String>[];
  Completer<void>? registerGate;
  bool fail = false, failRevocation = false;
  final confirmed = <PushRegistration>{};
  @override
  Future<PushDeviceRecord> register(PushRegistration registration) async {
    registered.add(registration);
    events.add('register:${registration.account.userId}');
    if (registerGate != null) await registerGate!.future;
    if (fail) throw StateError('unavailable');
    confirmed.add(registration);
    return PushDeviceRecord(
      id: '${registered.indexOf(registration) + 1}',
      registration: registration,
    );
  }

  @override
  Future<void> cleanup(PushAccount account, {String? exceptId}) async {
    for (var i = 0; i < registered.length; i++) {
      final r = registered[i];
      if (r.account.userId == account.userId &&
          '${i + 1}' != exceptId &&
          confirmed.contains(r) &&
          !revoked.contains(r) &&
          !fail) {
        await unregister(PushDeviceRecord(id: '${i + 1}', registration: r));
      }
    }
  }

  @override
  Future<void> unregister(PushDeviceRecord record) async {
    final registration = record.registration;
    revoked.add(registration);
    events.add('revoke:${registration.account.userId}');
    if (failRevocation) throw StateError('expired old account');
  }
}

Future<void> drainPush() async {
  // Flush stream events and chained SDK/backend jobs without real timers.
  for (var i = 0; i < 30; i++) {
    await Future<void>.value();
  }
}
