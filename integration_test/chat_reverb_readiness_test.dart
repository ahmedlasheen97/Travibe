import 'package:travibe/features/chats/data/reverb_socket.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:travibe/features/chats/data/reverb_readiness.dart';
import 'support/test_reporting.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerTestReporting(binding);
  testWidgets(
    'anonymous TLS and Reverb handshake are distinct from authorization and delivery',
    (tester) async {
      final result = await tester.runAsync(
        () => probeReverb(
          ReverbDeployment(
            base: Uri.parse('wss://travibeapp.com/reverb'),
            publicKey: 'e18855d51128bfdb7f62e5c6df983dfe',
          ),
        ),
      );
      expect(result, isNotNull);
      expect((result!['tls'] as Map)['verified'], true);
      expect(
        (result['pusher_protocol'] as Map)['connection_acknowledged'],
        true,
      );
      expect((result['anonymous_auth_gate'] as Map)['http_status'], 401);
      expect(result['subscription_verified'], false);
      expect(result['message_delivery_verified'], false);
      // No PreferencesManager, Firebase startup, bearer credential or private
      // subscription is used. Only sanitized stage outcomes leave the test.
      debugPrint('REVERB_ANONYMOUS_READINESS: ${jsonEncode(result)}');
      await tester.pumpWidget(const SizedBox());
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
  testWidgets(
    'production Pusher-protocol client connects anonymously without channel subscriptions',
    (tester) async {
      await tester.runAsync(() async {
        var authCalls = 0;
        final socket = PusherReverbSocket(
          authorize: (_, _) async {
            authCalls++;
            throw StateError('Anonymous probe must not authorize channels.');
          },
          onAuthFailure: (_) {},
        );
        try {
          final connected = socket.states
              .firstWhere((state) => state == ChatSocketState.connected)
              .timeout(const Duration(seconds: 25));
          socket.connect();
          expect(await connected, ChatSocketState.connected);
          expect(authCalls, 0);
        } finally {
          await socket.close();
        }
      });
      await tester.pumpWidget(const SizedBox());
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );
}
