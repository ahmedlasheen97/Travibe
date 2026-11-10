import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/features/chats/data/reverb_readiness.dart';
import 'package:travibe/features/chats/widgets/chat_widgets.dart';
import '../support/chat_e2e/chat_e2e_actor.dart';
import '../support/chat_e2e/chat_e2e_scenario.dart';

// Never pass bearer credentials through dart-define: it is compiled into apps.
// Only this non-secret execution gate is a compile-time option. Even if tokens
// exist in a developer shell, ordinary flutter test cannot perform writes.
const enabled = bool.fromEnvironment('TRAVIBE_CHAT_E2E_ENABLE');
void main() {
  testWidgets(
    'approved isolated two-account REST/display/Reverb scenario',
    (tester) async {
      final env = Platform.environment;
      if (env['TRAVIBE_CHAT_E2E_WRITE_APPROVAL'] !=
          'approved-test-accounts-only') {
        throw const ChatE2eFailure('explicit_write_approval_required');
      }
      final aid = env['TRAVIBE_CHAT_E2E_ACCOUNT_A_ID'] ?? '',
          bid = env['TRAVIBE_CHAT_E2E_ACCOUNT_B_ID'] ?? '';
      final realtime = env['TRAVIBE_CHAT_E2E_REALTIME'] == 'true';
      final decline = env['TRAVIBE_CHAT_E2E_SCENARIO'] == 'decline';
      final permit = ChatE2ePermit(
        accountA: aid,
        accountB: bid,
        writes: true,
        decline:
            decline &&
            env['TRAVIBE_CHAT_E2E_DECLINE_APPROVAL'] ==
                'delete-only-new-test-thread',
        channelAuthorization: realtime,
      );
      Dio driver() {
        final dio = Dio();
        // Opt-in live test client only. Bypass Flutter's fake test HTTP adapter,
        // never authentication/TLS validation. No application session is changed.
        dio.httpClientAdapter = IOHttpClientAdapter(
          createHttpClient: () => HttpOverrides.runWithHttpOverrides(
            HttpClient.new,
            _LiveDriverHttpOverrides(),
          ),
        );
        return dio;
      }

      final a = ChatE2eHttpActor(
        id: aid,
        token: env['TRAVIBE_CHAT_E2E_TOKEN_A'] ?? '',
        permit: permit,
        dio: driver(),
      );
      ChatE2eHttpActor? b;
      try {
        b = ChatE2eHttpActor(
          id: bid,
          token: env['TRAVIBE_CHAT_E2E_TOKEN_B'] ?? '',
          permit: permit,
          dio: driver(),
        );
        final result = await tester.runAsync(
          () => runChatE2e(
            a: a,
            b: b!,
            deployment: ReverbDeployment(
              base: Uri.parse('wss://travibeapp.com/reverb'),
              publicKey: 'e18855d51128bfdb7f62e5c6df983dfe',
            ),
            realtime: realtime,
            decline: decline,
          ),
        );
        expect(result, isNotNull);
        if (result!.message case final message?) {
          // Render only the newly generated approved test message, never history.
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ChatMessageBubble(message: message, outgoing: false),
              ),
            ),
          );
          expect(find.text(message.text), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
        }
        // Outcomes only. No IDs, text, auth signatures, tokens or attachment URLs.
        debugPrint('CHAT_E2E_VERIFIED_STAGES: ${result.stages.keys.join(',')}');
      } finally {
        a.close();
        b?.close();
      }
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

// Uses the platform HttpClient implementation inside the explicitly enabled test zone.
class _LiveDriverHttpOverrides extends HttpOverrides {}
