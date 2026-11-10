import 'package:travibe/features/chats/cubit/chat_discovery_cubit.dart';
import 'package:travibe/features/chats/widgets/chat_widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/dio_client.dart';
import 'package:dio/dio.dart';
import 'package:travibe/features/chats/screens/chats_screen.dart';
import 'package:travibe/features/chats/screens/new_conversation_screen.dart';
import 'package:travibe/features/onboarding/screens/splash_screen.dart';
import 'package:travibe/features/onboarding/screens/onboarding_screen.dart';
import 'package:travibe/features/auth/screens/login_screen.dart';
import 'package:travibe/features/auth/screens/otp_verification_screen.dart';
import 'package:travibe/features/profilesetup/screens/profile_setup_screen.dart';
import 'package:travibe/main.dart' as app;
import 'package:travibe/root.dart';
import 'support/test_reporting.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerTestReporting(binding);
  testWidgets('persisted startup opens Home Chats without guessed API mutations', (
    tester,
  ) async {
    await PreferencesManager().init();
    await tester.pumpWidget(const app.MyApp());
    await tester.pump();
    bool ready() => [
      Root,
      LoginScreen,
      OnboardingScreen,
      OtpVerificationScreen,
      ProfileSetupScreen,
    ].any((type) => find.byType(type).evaluate().isNotEmpty);
    for (var i = 0; i < 120 && !ready(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.byType(SplashScreen), findsNothing);
    expect(
      ready(),
      isTrue,
      reason: 'Startup did not reach a terminal guarded route.',
    );
    debugPrint(
      'CHAT_STARTUP_AUDIT: session=${PreferencesManager().hasSession}; route=${[Root, LoginScreen, OnboardingScreen, OtpVerificationScreen, ProfileSetupScreen].where((type) => find.byType(type).evaluate().isNotEmpty).join(',')}',
    );
    if (find.byType(Root).evaluate().isEmpty) {
      debugPrint(
        'CHAT_SIMULATOR: guarded startup; no authenticated session available. Chat navigation not verified.',
      );
    } else {
      // Read-only contract diagnostics: field names/types only, never values,
      // message bodies, IDs, bearer credentials or private attachment URLs.
      for (final endpoint in ['conversations', 'conversations/requests']) {
        try {
          final response = await DioClient().dio
              .get<Object?>(
                endpoint,
                options: Options(
                  receiveTimeout: const Duration(seconds: 12),
                  extra: {
                    'sessionRevision': PreferencesManager().sessionRevision,
                  },
                ),
              )
              .timeout(const Duration(seconds: 15));
          debugPrint(
            'CHAT_REST_AUDIT $endpoint: HTTP ${response.statusCode}; shape=${_shape(response.data)}',
          );
          final data = response.data;
          if (data is Map && data['meta'] is Map) {
            final meta = data['meta'] as Map;
            final numbers = {
              for (final key in [
                'current_page',
                'last_page',
                'per_page',
                'total',
              ])
                if (meta[key] is num) key: meta[key],
            };
            debugPrint('CHAT_PAGINATION_AUDIT $endpoint: $numbers');
          }
        } on DioException catch (error) {
          debugPrint(
            'CHAT_REST_AUDIT $endpoint: HTTP ${error.response?.statusCode}; transport=${error.type.name}',
          );
        } catch (_) {
          debugPrint('CHAT_REST_AUDIT $endpoint: unavailable or timed out');
        }
      }
      await tester.tap(find.byKey(const ValueKey('home-messages-button')));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 20),
      );
      expect(find.byType(ChatsScreen), findsOneWidget);
      expect(
        find.byType(ChatListTile).evaluate().isNotEmpty ||
            find.text('No messages yet').evaluate().isNotEmpty,
        isTrue,
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(
        find.byType(ChatListTile).evaluate().isNotEmpty ||
            find.text('No messages yet').evaluate().isNotEmpty,
        isTrue,
      );
      await tester.tap(find.textContaining('Requests ('));
      await tester.pumpAndSettle();
      expect(
        find.byType(ChatListTile).evaluate().isNotEmpty ||
            find.text('No message requests').evaluate().isNotEmpty,
        isTrue,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('New conversation'));
      await tester.pumpAndSettle();
      expect(find.byType(NewConversationScreen), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'trav');
      await tester.pump(const Duration(milliseconds: 400));
      final discovery = tester
          .widget<BlocBuilder<ChatDiscoveryCubit, ChatDiscoveryState>>(
            find.byType(BlocBuilder<ChatDiscoveryCubit, ChatDiscoveryState>),
          )
          .bloc!;
      for (
        var i = 0;
        i < 80 && discovery.state.status == ChatDiscoveryStatus.loading;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 250)),
        );
        await tester.pump(const Duration(milliseconds: 250));
      }
      debugPrint(
        'CHAT_DISCOVERY_AUDIT: status=${discovery.state.status.name}; matches=${discovery.state.users.length}; error=${discovery.state.error?.statusCode}',
      );
      expect(
        discovery.state.status,
        ChatDiscoveryStatus.loaded,
        reason: 'Read-only discovery did not complete successfully.',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ChatsScreen), findsOneWidget);
      debugPrint(
        'CHAT_SIMULATOR: restored Home -> live Chats -> refresh -> Requests -> New Conversation -> user search -> Back verified. No conversation created, message fetched, read receipt changed or message sent.',
      );
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}

Object _shape(Object? value, [int depth = 0]) {
  if (depth > 5) return 'nested';
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): _shape(entry.value, depth + 1),
    };
  }
  if (value is List) {
    return value.isEmpty ? 'empty-list' : [_shape(value.first, depth + 1)];
  }
  return value == null
      ? 'null'
      : value is bool
      ? 'boolean'
      : value is num
      ? 'number'
      : 'string';
}
