import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/constants/feature_flags.dart';
import 'package:travibe/features/explore/screens/explore_screen.dart';

Future<void> _pump(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: const Size(390, 844),
        padding: const EdgeInsets.only(top: 47, bottom: 34),
        disableAnimations: reduceMotion,
      ),
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          locale: locale,
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const ExploreScreen(),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('coming soon fits 390×844 with title, copy and previews', (
    tester,
  ) async {
    await _pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Explore'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(find.text('Coming soon'), findsOneWidget);
    expect(
      find.textContaining('Discover destinations, hotels and hidden gems.'),
      findsOneWidget,
    );
    for (final label in ['Destinations', 'Hotels', 'Trips', 'Local guides']) {
      expect(find.text(label), findsOneWidget);
    }
    // Previews are decorative: faded and not tappable.
    final previews = find.byKey(const ValueKey('explore-previews'));
    expect(
      find.descendant(of: previews, matching: find.byType(InkWell)),
      findsNothing,
    );
    expect(
      find.descendant(of: previews, matching: find.byType(GestureDetector)),
      findsNothing,
    );
    expect(
      tester
          .widget<Opacity>(
            find.ancestor(of: previews, matching: find.byType(Opacity)),
          )
          .opacity,
      lessThan(1),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('explore-illustration')),
        matching: find.image(const AssetImage(ExploreScreen.illustration)),
      ),
      findsOneWidget,
    );
    // No scrolling: everything sits inside the visible screen.
    expect(find.byType(Scrollable), findsNothing);
    for (final key in ['explore-illustration', 'explore-previews']) {
      final rect = tester.getRect(find.byKey(ValueKey(key)));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(844 - 34));
    }
  });

  testWidgets('illustration floats, and stays still with reduced motion', (
    tester,
  ) async {
    Rect art() =>
        tester.getRect(find.byKey(const ValueKey('explore-illustration')));
    await _pump(tester);
    final before = art();
    await tester.pump(const Duration(milliseconds: 1200));
    expect(art(), isNot(before));

    await _pump(tester, reduceMotion: true);
    final still = art();
    await tester.pump(const Duration(milliseconds: 1200));
    expect(art(), still);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('Arabic renders RTL without overflow', (tester) async {
    await _pump(tester, locale: const Locale('ar'));
    expect(tester.takeException(), isNull);
    expect(find.text('استكشف'), findsOneWidget);
    expect(find.text('قريبًا'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('قريبًا'))),
      TextDirection.rtl,
    );
  });

  test('currency row and saved hotels stay hidden', () {
    expect(kShowCurrencySetting, isFalse);
    expect(kShowSavedHotels, isFalse);
  });
}
