import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/onboarding/cubit/startup_cubit.dart';
import 'package:travibe/features/onboarding/screens/splash_screen.dart';
import 'package:travibe/features/onboarding/screens/startup_screen.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'onboarding_fixtures.dart';

void main() {
  final preferences = PreferencesManager();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.completeOnboarding();
    await preferences.saveToken('candidate');
  });
  tearDown(() => preferences.clear());
  Future<void> show(
    WidgetTester tester,
    StartupAuth auth,
    List<StartupTarget> exits, {
    bool reduced = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: StartupScreen(
            auth: auth,
            onboardingRepo: FakeOnboardingRepo(),
            onReady: (decision) => exits.add(decision.target),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await Future.wait([
        const SvgAssetLoader(SplashScreen.symbolAsset).loadBytes(null),
        const SvgAssetLoader(SplashScreen.wordmarkAsset).loadBytes(null),
      ]);
    });
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'ready authentication waits for unchanged 1500ms splash, exits once',
    (tester) async {
      final exits = <StartupTarget>[];
      await show(tester, StartupAuth(), exits);
      expect(SplashScreen.duration, const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 1499));
      expect(exits, isEmpty);
      await tester.pump(const Duration(milliseconds: 2));
      await tester.pump();
      expect(exits, [StartupTarget.home]);
      await tester.pump(const Duration(seconds: 3));
      expect(exits, [StartupTarget.home]);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'slow validation retains full orange splash until ready with no interim exit',
    (tester) async {
      final gate = Completer<ProfileModel>();
      final auth = StartupAuth()..handler = () => gate.future;
      final exits = <StartupTarget>[];
      await show(tester, auth, exits);
      await tester.pump(const Duration(milliseconds: 1501));
      expect(exits, isEmpty);
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(
        tester
            .widget<Opacity>(find.byKey(const ValueKey('splash-symbol')))
            .opacity,
        0,
      );
      gate.complete(startupUser());
      await tester.pump();
      await tester.pump();
      expect(exits, [StartupTarget.home]);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'failed validation retains token, retry navigates without replaying splash',
    (tester) async {
      final auth = StartupAuth()
        ..handler = () async => throw ApiError(message: 'Offline');
      final exits = <StartupTarget>[];
      await show(tester, auth, exits);
      await tester.pump(const Duration(milliseconds: 1501));
      await tester.pump();
      expect(find.text('Retry'), findsNothing, reason: 'still retrying');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pump();
      expect(auth.calls, 3);
      expect(exits, isEmpty);
      expect(preferences.hasSession, true);
      final message = find.byKey(const ValueKey('startup-error'));
      expect(message, findsOneWidget);
      // A Material ancestor: no yellow debug underlines.
      expect(
        find.ancestor(of: message, matching: find.byType(Scaffold)),
        findsOneWidget,
      );
      expect(tester.widget<Text>(message).style?.color, Colors.white);
      expect(find.byKey(const ValueKey('startup-retry')), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      final gate = Completer<ProfileModel>();
      auth.handler = () => gate.future;
      await tester.tap(find.byKey(const ValueKey('startup-retry')));
      await tester.pump();
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      gate.complete(startupUser());
      await tester.pump();
      await tester.pump();
      expect(exits, [StartupTarget.home]);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('a failure while backgrounded is retried on resume', (
    tester,
  ) async {
    final auth = StartupAuth()
      ..handler = () async => throw ApiError(message: 'Offline');
    final exits = <StartupTarget>[];
    await show(tester, auth, exits);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(auth.calls, 3);
    auth.handler = () async => startupUser();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(auth.calls, 4);
    // The splash motion paused with the app; it finishes before navigating.
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();
    expect(exits, [StartupTarget.home]);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'startup readiness while backgrounded waits for resume and remaining motion',
    (tester) async {
      final gate = Completer<ProfileModel>();
      final auth = StartupAuth()..handler = () => gate.future;
      final exits = <StartupTarget>[];
      await show(tester, auth, exits);
      await tester.pump(const Duration(milliseconds: 300));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      gate.complete(startupUser());
      await tester.pump(const Duration(seconds: 10));
      expect(exits, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1201));
      await tester.pump();
      expect(exits, [StartupTarget.home]);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'reduced motion still waits for validation, with no extra animation delay',
    (tester) async {
      final gate = Completer<ProfileModel>();
      final auth = StartupAuth()..handler = () => gate.future;
      final exits = <StartupTarget>[];
      await show(tester, auth, exits, reduced: true);
      expect(exits, isEmpty);
      gate.complete(startupUser());
      await tester.pump();
      await tester.pump();
      expect(exits, [StartupTarget.home]);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('disposing startup ignores late session validation', (
    tester,
  ) async {
    final gate = Completer<ProfileModel>();
    final auth = StartupAuth()..handler = () => gate.future;
    final exits = <StartupTarget>[];
    await show(tester, auth, exits);
    await tester.pumpWidget(const SizedBox());
    gate.complete(startupUser());
    await tester.pump(const Duration(seconds: 3));
    expect(exits, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
