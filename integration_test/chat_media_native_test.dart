import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:travibe/features/chats/data/chat_device_media.dart';
import 'support/test_reporting.dart';

/// No app main, account, networking, live uploads or microphone recording.
/// Gallery check is explicitly opt-in and saves one local 1px PNG to Simulator.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerTestReporting(binding);
  testWidgets(
    'native microphone status is available without requesting access',
    (tester) async {
      final status = await tester.runAsync(
        () => const ChatDeviceMedia().microphone(),
      );
      expect(status, isIn(ChatMicrophonePermission.values));
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: Text('Native media permission check')),
          ),
        ),
      );
    },
  );
  testWidgets(
    'native network route status is optional and never requests permission',
    (tester) async {
      final value = await tester.runAsync(
        () => const MethodChannel(
          'travibe/chat_media',
        ).invokeMethod<bool>('networkStatus'),
      );
      expect(value, anyOf(isNull, isA<bool>()));
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: Text('Native connectivity check')),
          ),
        ),
      );
    },
  );
  if (const bool.fromEnvironment('CHAT_TEST_LOCAL_GALLERY')) {
    testWidgets('native add-only Photos operation saves a local image fixture', (
      tester,
    ) async {
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aKp8AAAAASUVORK5CYII=',
      );
      await tester.runAsync(() => const ChatDeviceMedia().saveImage(bytes));
      await tester.pumpWidget(const SizedBox());
    });
  }
}
