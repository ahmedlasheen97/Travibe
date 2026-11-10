import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/notifications/firebase_messaging_client.dart';
import 'package:travibe/core/notifications/push_message.dart';
import 'package:travibe/core/notifications/push_notification_service.dart';
import 'push_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final prefs = PreferencesManager();
  late FakeMessagingClient client;
  late FakePushRepository repo;
  late PushNotificationService service;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'_token': 'auth-a'});
    await prefs.init();
    client = FakeMessagingClient();
    repo = FakePushRepository();
    service = PushNotificationService(client: client, repository: repo);
  });
  tearDown(() async {
    service.dispose();
    await client.close();
    await prefs.clear();
  });
  Future<void> bind([String id = '1']) async {
    await service.updateAccount(id, expectedSession: prefs.sessionRevision);
    await service.start();
    await drainPush();
  }

  test(
    'all SDK authorization values including permanent denial are mapped',
    () {
      for (final status in AuthorizationStatus.values) {
        final mapped = FirebaseMessagingClient.permissionFromStatus(status);
        expect(mapped, switch (status) {
          AuthorizationStatus.authorized => PushPermission.authorized,
          AuthorizationStatus.provisional => PushPermission.provisional,
          AuthorizationStatus.notDetermined => PushPermission.notDetermined,
          AuthorizationStatus.denied ||
          AuthorizationStatus.deniedPermanently => PushPermission.denied,
        });
      }
    },
  );
  test(
    'initialization coalesces; stored credentials alone never register',
    () async {
      await Future.wait([service.start(), service.start()]);
      await drainPush();
      expect(client.starts, 1);
      expect(client.prompts, 0);
      expect(client.reads, 0);
      expect(repo.registered, isEmpty);
      await service.updateAccount(null, expectedSession: prefs.sessionRevision);
      await service.updateAccount(
        'invalid',
        expectedSession: prefs.sessionRevision,
      );
      expect(repo.registered, isEmpty);
      await bind('001');
      expect(repo.registered.single.account.userId, '1');
      expect(repo.registered.single.account.authorizationToken, 'auth-a');
    },
  );
  test('unsupported initialization is safe and does not change auth', () async {
    client.available = false;
    await bind();
    expect(service.supported, false);
    expect(repo.registered, isEmpty);
    expect(await prefs.getToken(), 'auth-a');
  });
  for (final status in [
    PushPermission.denied,
    PushPermission.notDetermined,
    PushPermission.unknown,
  ]) {
    test('$status never reads token or prompts automatically', () async {
      client.status = status;
      await bind();
      expect(client.reads, 0);
      expect(client.prompts, 0);
      expect(repo.registered, isEmpty);
    });
  }
  test(
    'permission requests coalesce and provisional access retrieves token',
    () async {
      client.status = PushPermission.notDetermined;
      await bind();
      client.permissionGate = Completer<PushPermission>();
      final a = service.requestPermission(), b = service.requestPermission();
      await drainPush();
      expect(client.prompts, 1);
      client.permissionGate!.complete(PushPermission.provisional);
      await Future.wait([a, b]);
      await drainPush();
      expect(service.permission, PushPermission.provisional);
      expect(repo.registered, hasLength(1));
    },
  );
  test('revoked OS permission revokes captured registration', () async {
    await bind();
    client.status = PushPermission.denied;
    await service.resume();
    await drainPush();
    expect(repo.revoked.single.account.authorizationToken, 'auth-a');
    expect(client.deletes, greaterThan(0));
  });
  testWidgets(
    'APNs retries are bounded and token waits for Apple registration',
    (tester) async {
      client.apns = null;
      service.dispose();
      service = PushNotificationService(
        client: client,
        repository: repo,
        retryDelays: const [Duration(seconds: 1), Duration(seconds: 2)],
      );
      await bind();
      final initial = client.apnsReads;
      expect(service.tokenStatus, PushTokenStatus.waitingForApns);
      expect(client.reads, 0);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 10));
      expect(client.apnsReads, initial + 2);
      client.apns = 'ready';
      await service.resume();
      await drainPush();
      expect(repo.registered, hasLength(1));
    },
  );
  test('refresh dedupes registration and ignores stale event token', () async {
    await bind();
    client.tokens.add('device-a');
    await drainPush();
    expect(repo.registered, hasLength(1));
    client.currentToken = 'device-b';
    client.tokens.add('stale-device-a');
    await drainPush();
    expect(repo.registered.last.token, 'device-b');
    expect(repo.revoked.single.token, 'device-a');
  });
  test(
    'logout revokes using old credentials and cancels pending navigation',
    () async {
      await bind();
      service.setNavigationHandler(null);
      client.taps.add(PushMessage(id: 'tap'));
      await drainPush();
      await prefs.clearSession();
      await drainPush();
      var opens = 0;
      service.setNavigationHandler(() => opens++);
      expect(opens, 0);
      expect(client.deletes, greaterThan(0));
      expect(repo.revoked.single.account.authorizationToken, 'auth-a');
    },
  );
  test(
    'account switch waits for old register before revoke and new register',
    () async {
      repo.registerGate = Completer<void>();
      await bind();
      expect(repo.registered, hasLength(1));
      await prefs.saveToken('auth-b');
      client.currentToken = 'device-b';
      await bind('2');
      expect(repo.events, ['register:1']);
      repo.registerGate!.complete();
      await drainPush();
      expect(repo.events, ['register:1', 'revoke:1', 'register:2']);
      expect(repo.revoked.single.account.authorizationToken, 'auth-a');
      expect(repo.registered.last.account.authorizationToken, 'auth-b');
      expect(repo.registered.last.token, 'device-b');
      expect(service.backendStatus, PushBackendStatus.registered);
    },
  );
  test(
    'in-flight old token result cannot bind to replacement account',
    () async {
      client.tokenGate = Completer<String?>();
      await bind();
      await prefs.saveToken('auth-b');
      final oldGate = client.tokenGate!;
      client.tokenGate = null;
      client.currentToken = 'device-b';
      await bind('2');
      oldGate.complete('device-a');
      await drainPush();
      expect(repo.registered.single.account.userId, '2');
      expect(repo.registered.single.token, 'device-b');
    },
  );
  test(
    'unverified backend is not called and failures can retry safely',
    () async {
      repo.supported = false;
      await bind();
      expect(service.backendStatus, PushBackendStatus.unsupported);
      expect(service.tokenStatus, PushTokenStatus.ready);
      expect(repo.events, isEmpty);
    },
  );
  test('backend error preserves credentials and retry recovers', () async {
    repo.fail = true;
    await bind();
    expect(service.backendStatus, PushBackendStatus.failed);
    expect(await prefs.getToken(), 'auth-a');
    repo.fail = false;
    await service.retry();
    await drainPush();
    expect(service.backendStatus, PushBackendStatus.registered);
  });
  test(
    'foreground and tap dedupe separately; taps wait for authenticated root',
    () async {
      client.initial = PushMessage(
        id: 'same',
        data: {'route': '/unsafe', 'user_id': 999},
      );
      await service.start();
      var opens = 0;
      final activity = <PushActivity>[];
      final sub = service.activities.listen(activity.add);
      service.setNavigationHandler(() => opens++);
      expect(opens, 0);
      await bind();
      expect(opens, 1);
      client.taps.add(client.initial!);
      client.taps.add(client.initial!);
      client.messages.add(client.initial!);
      client.messages.add(client.initial!);
      await drainPush();
      expect(opens, 1);
      expect(
        activity.where((a) => a.kind == PushActivityKind.foreground),
        hasLength(1),
      );
      await sub.cancel();
    },
  );
  test(
    'dispose cancels all SDK listeners without treating shutdown as logout',
    () async {
      await bind();
      service.dispose();
      await drainPush();
      expect(client.tokens.hasListener, false);
      expect(client.messages.hasListener, false);
      expect(client.taps.hasListener, false);
      expect(repo.revoked, isEmpty);
    },
  );
  test('logout during POST revokes its returned ID after completion', () async {
    repo.registerGate = Completer<void>();
    await bind();
    await prefs.clearSession();
    await drainPush();
    expect(repo.revoked, isEmpty);
    repo.registerGate!.complete();
    await drainPush();
    expect(repo.revoked, hasLength(1));
    expect(repo.revoked.single.account.authorizationToken, 'auth-a');
    expect(service.backendStatus, PushBackendStatus.idle);
  });
  test('rapid A B C switches skip stale B and keep only C current', () async {
    repo.registerGate = Completer<void>();
    await bind();
    await prefs.saveToken('auth-b');
    client.currentToken = 'device-b';
    await bind('2');
    await prefs.saveToken('auth-c');
    client.currentToken = 'device-c';
    await bind('3');
    repo.registerGate!.complete();
    await drainPush();
    expect(repo.registered.map((r) => r.account.userId), ['1', '3']);
    expect(repo.revoked.single.account.userId, '1');
    expect(repo.registered.last.token, 'device-c');
    expect(service.backendStatus, PushBackendStatus.registered);
  });
  test(
    'failed refreshed registration leaves previous record available for logout cleanup',
    () async {
      await bind();
      repo.fail = true;
      client.currentToken = 'device-b';
      client.tokens.add('device-b');
      await drainPush();
      expect(service.backendStatus, PushBackendStatus.failed);
      expect(repo.revoked, isEmpty);
      await prefs.clearSession();
      await drainPush();
      expect(repo.revoked.single.token, 'device-a');
    },
  );
  test(
    'shutdown during registration retains server record for terminated delivery',
    () async {
      repo.registerGate = Completer<void>();
      await bind();
      service.dispose();
      repo.registerGate!.complete();
      await drainPush();
      expect(repo.revoked, isEmpty);
    },
  );
  test(
    'expired old cleanup cannot publish an error into replacement account',
    () async {
      await bind();
      repo.failRevocation = true;
      await prefs.saveToken('auth-b');
      client.currentToken = 'device-b';
      await bind('2');
      expect(service.backendStatus, PushBackendStatus.registered);
      expect(service.error, isNull);
    },
  );
  test(
    'FCM retrieval failure preserves auth and never registers a placeholder',
    () async {
      client.tokenFailure = StateError('simulator capability unavailable');
      await bind();
      expect(service.tokenStatus, PushTokenStatus.failed);
      expect(repo.registered, isEmpty);
      expect(await prefs.getToken(), 'auth-a');
    },
  );
  test('blank SDK token is rejected without registration', () async {
    client.currentToken = '   ';
    await bind();
    expect(service.tokenStatus, PushTokenStatus.failed);
    expect(repo.registered, isEmpty);
  });
  test('message parsing dedupes reordered maps and redacts diagnostics', () {
    final a = PushMessage.fromRemote(
      const RemoteMessage(messageId: 'id', data: {'route': '/unsafe'}),
    );
    expect(a.id, 'id');
    expect(a.key, 'id:id');
    expect(a.toString(), isNot(contains('/unsafe')));
    expect(
      PushMessage(data: {'a': 1, 'b': 2}).key,
      PushMessage(data: {'b': 2, 'a': 1}).key,
    );
  });
}
