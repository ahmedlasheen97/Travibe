import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/routing/router_generator.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/auth/screens/login_screen.dart';
import 'package:travibe/features/auth/screens/sign_up_screen.dart';
import 'onboarding_fixtures.dart';
import 'package:travibe/features/onboarding/screens/splash_screen.dart';
import 'package:travibe/features/onboarding/screens/onboarding_screen.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

Future<void> showSplash(
  WidgetTester tester,
  VoidCallback complete, {
  bool reduced = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          disableAnimations: reduced,
          padding: const EdgeInsets.only(top: 44, bottom: 34),
          viewPadding: const EdgeInsets.only(top: 44, bottom: 34),
        ),
        child: SplashScreen(onComplete: complete),
      ),
    ),
  );
  // Compile the real SVGs before advancing the deterministic animation clock.
  await tester.runAsync(() async {
    await Future.wait([
      const SvgAssetLoader(SplashScreen.symbolAsset).loadBytes(null),
      const SvgAssetLoader(SplashScreen.wordmarkAsset).loadBytes(null),
    ]);
  });
  await tester.pump();
  await tester.pump();
}

SplashExpansionPainter expansion(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.byKey(const ValueKey('splash-orange-expansion')),
            )
            .painter!
        as SplashExpansionPainter;

Opacity opacity(WidgetTester tester, String key) =>
    tester.widget<Opacity>(find.byKey(ValueKey(key)));

RotationTransition rotation(WidgetTester tester) =>
    tester.widget<RotationTransition>(
      find.byKey(const ValueKey('splash-symbol-rotation')),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts = FontLoader('Plus Jakarta Sans')
      ..addFont(rootBundle.load('assets/fonts/PlusJakartaSans-Regular.ttf'));
    await fonts.load();
  });
  testWidgets(
    'black intro, bottom entrance, branding, symbol expansion and one exit',
    (tester) async {
      var exits = 0;
      expect(SplashScreen.duration, const Duration(milliseconds: 1500));
      await showSplash(tester, () => exits++);
      final symbol = find.byKey(const ValueKey('splash-symbol'));
      final viewport = tester.getSize(find.byType(Scaffold));
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        Colors.black,
      );
      expect(find.byType(SvgPicture), findsNWidgets(2));
      expect(tester.getTopLeft(symbol).dy, greaterThan(viewport.height));
      expect(opacity(tester, 'splash-wordmark').opacity, 0);
      final initialY = tester.getCenter(symbol).dy;
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getCenter(symbol).dy, lessThan(initialY));
      expect(tester.getCenter(symbol).dy, greaterThan(viewport.height / 2));
      expect(tester.getCenter(symbol).dx, viewport.width / 2);
      expect(opacity(tester, 'splash-wordmark').opacity, 0);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getCenter(symbol), viewport.center(Offset.zero));
      expect(opacity(tester, 'splash-wordmark').opacity, 0);
      await tester.pump(const Duration(milliseconds: 300));
      expect(opacity(tester, 'splash-wordmark').opacity, closeTo(1, .00001));
      expect(expansion(tester).radius, closeTo(0, .00001));
      await tester.pump(const Duration(milliseconds: 200));
      expect(expansion(tester).radius, greaterThan(0));
      expect(expansion(tester).center, tester.getCenter(symbol));
      expect(exits, 0);
      await tester.pump(const Duration(milliseconds: 399));
      expect(exits, 0);
      // Cross the final vsync boundary; controller duration remains exactly 1500ms.
      await tester.pump(const Duration(milliseconds: 2));
      final finalExpansion = expansion(tester);
      expect(finalExpansion.center, viewport.center(Offset.zero));
      for (final corner in [
        Offset.zero,
        Offset(viewport.width, 0),
        Offset(0, viewport.height),
        Offset(viewport.width, viewport.height),
      ]) {
        expect(
          finalExpansion.radius,
          greaterThan((corner - finalExpansion.center).distance),
        );
      }
      expect(opacity(tester, 'splash-symbol').opacity, 0);
      expect(opacity(tester, 'splash-wordmark').opacity, 0);
      expect(exits, 1);
      await tester.pump(const Duration(seconds: 10));
      expect(exits, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('final expansion paints every pixel solid primary orange', (
    tester,
  ) async {
    await showSplash(tester, () {});
    await tester.pump(SplashScreen.duration + const Duration(milliseconds: 1));
    final painter = expansion(tester);
    final size = tester.getSize(find.byType(Scaffold));
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), size);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(size.width.toInt(), size.height.toInt());
    final data = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    final bytes = data!.buffer.asUint8List();
    for (var i = 0; i < bytes.length; i += 4) {
      if (bytes[i] != 228 ||
          bytes[i + 1] != 92 ||
          bytes[i + 2] != 16 ||
          bytes[i + 3] != 255) {
        fail('Final orange frame has an unfilled pixel at byte $i');
      }
    }
    image.dispose();
    picture.dispose();
  });

  testWidgets('SVG turns once around its center during the smooth entrance', (
    tester,
  ) async {
    await showSplash(tester, () {});
    final symbol = find.byKey(const ValueKey('splash-symbol'));
    final viewport = tester.getSize(find.byType(Scaffold));
    final startY = tester.getCenter(symbol).dy;
    expect(rotation(tester).turns.value, 0);
    expect(rotation(tester).alignment, Alignment.center);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('splash-symbol-rotation')),
        matching: find.byType(SvgPicture),
      ),
      findsOneWidget,
    );
    var previousY = startY;
    for (var step = 1; step <= 4; step++) {
      await tester.pump(const Duration(milliseconds: 150));
      final progress = step / 4;
      expect(rotation(tester).turns.value, closeTo(progress, .000001));
      final center = tester.getCenter(symbol);
      expect(center.dx, closeTo(viewport.width / 2, .000001));
      expect(center.dy, lessThan(previousY));
      expect(
        center.dy,
        closeTo(
          viewport.height / 2 +
              (startY - viewport.height / 2) *
                  (1 - Curves.easeOutCubic.transform(progress)),
          .000001,
        ),
      );
      expect(opacity(tester, 'splash-wordmark').opacity, 0);
      previousY = center.dy;
    }
    expect(tester.getCenter(symbol), viewport.center(Offset.zero));
    await tester.pump(const Duration(milliseconds: 150));
    expect(rotation(tester).turns.value, 1);
    expect(opacity(tester, 'splash-wordmark').opacity, greaterThan(0));
    expect(opacity(tester, 'splash-wordmark').opacity, lessThan(1));
    await tester.pump(const Duration(milliseconds: 751));
    expect(rotation(tester).turns.value, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion shows static branding and exits promptly', (
    tester,
  ) async {
    var exits = 0;
    await showSplash(tester, () => exits++, reduced: true);
    expect(opacity(tester, 'splash-symbol').opacity, 1);
    expect(rotation(tester).turns.value, 0);
    expect(expansion(tester).radius, 0);
    expect(opacity(tester, 'splash-wordmark').opacity, closeTo(1, .00001));
    await tester.pump();
    expect(exits, 1);
  });

  testWidgets('disposal prevents navigation and releases ticker', (
    tester,
  ) async {
    var exits = 0;
    await showSplash(tester, () => exits++);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    expect(exits, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('background pauses timeline and resume continues it', (
    tester,
  ) async {
    var exits = 0;
    await showSplash(tester, () => exits++);
    await tester.pump(const Duration(milliseconds: 300));
    final pausedTurns = rotation(tester).turns.value;
    final pausedCenter = tester.getCenter(
      find.byKey(const ValueKey('splash-symbol')),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 10));
    expect(rotation(tester).turns.value, pausedTurns);
    expect(
      tester.getCenter(find.byKey(const ValueKey('splash-symbol'))),
      pausedCenter,
    );
    expect(exits, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1199));
    expect(exits, 0);
    await tester.pump(const Duration(milliseconds: 2));
    expect(exits, 1);
  });

  testWidgets('ordinary rebuild keeps the original timeline', (tester) async {
    var exits = 0;
    void complete() => exits++;
    await showSplash(tester, complete);
    await tester.pump(const Duration(milliseconds: 900));
    expect(opacity(tester, 'splash-wordmark').opacity, closeTo(1, .00001));
    await showSplash(tester, complete);
    expect(opacity(tester, 'splash-wordmark').opacity, closeTo(1, .00001));
    await tester.pump(const Duration(milliseconds: 601));
    expect(exits, 1);
  });

  for (final size in [const Size(280, 480), const Size(1024, 768)]) {
    testWidgets('branding stays centered without overflow at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await showSplash(tester, () {});
      await tester.pump(const Duration(milliseconds: 900));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 601));
      expect(expansion(tester).center, size.center(Offset.zero));
      expect(
        expansion(tester).radius,
        greaterThan(size.center(Offset.zero).distance),
      );
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final session in [false, true]) {
    testWidgets(
      'startup uses completion flag and invalid session safeguard: $session',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        await PreferencesManager().init();
        if (session) {
          await PreferencesManager().completeOnboarding();
          await PreferencesManager().saveToken('test-token');
        }
        final router = RouterGenerator.createRouter(
          auth: InvalidStartupAuth(),
          onboardingRepo: FakeOnboardingRepo(),
        );
        router.go('/splash');
        await tester.pumpWidget(
          ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, _) =>
                MaterialApp.router(theme: darkTheme, routerConfig: router),
          ),
        );
        await tester.pump();
        expect(find.byType(SplashScreen), findsOneWidget);
        expect(find.byType(LoginScreen), findsNothing);
        expect(find.byType(OnboardingScreen), findsNothing);
        await tester.pumpAndSettle();
        await tester.pump(SplashScreen.duration);
        await tester.pumpAndSettle();
        expect(
          find.byType(LoginScreen),
          session ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(OnboardingScreen),
          session ? findsNothing : findsOneWidget,
        );
        expect(find.byType(SplashScreen), findsNothing);
        expect(router.canPop(), isFalse);
        if (!session) {
          await tester.ensureVisible(find.text('Next'));
          await tester.tap(find.text('Next'));
          await tester.pumpAndSettle();
          expect(find.text('Plan journeys from the server'), findsOneWidget);
          expect(find.byType(LoginScreen), findsNothing);
          await tester.ensureVisible(find.text('Next'));
          await tester.tap(find.text('Next'));
          await tester.pumpAndSettle();
          expect(find.text('Travel together from the server'), findsOneWidget);
          await tester.ensureVisible(find.text('Get Started'));
          await tester.drag(
            find.byIcon(Icons.arrow_forward_ios),
            const Offset(320, 0),
          );
          await tester.pumpAndSettle();
          expect(find.byType(SignUpScreen), findsOneWidget);
          expect(PreferencesManager().onboardingCompleted, true);
        }
        await tester.pumpWidget(const SizedBox());
        router.dispose();
        await PreferencesManager().clear();
      },
    );
  }
}
