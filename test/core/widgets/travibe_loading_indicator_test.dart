import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/travibe_loading_indicator.dart';

void main() {
  Future<void> show(
    WidgetTester tester, {
    double size = 64,
    bool motion = true,
    Color? color,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        // An orange theme must not leak into the loader.
        theme: ThemeData(primaryColor: DarkColors.primaryColor),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: !motion),
          child: Center(
            child: TravibeLoadingIndicator(size: size, color: color),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  for (final size in [64.0, 32.0]) {
    testWidgets(
      'one native white radius-15 indicator in a ${size}px centered frame',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await show(tester, size: size);
        final indicator = tester.widget<CupertinoActivityIndicator>(
          find.byType(CupertinoActivityIndicator),
        );
        expect(indicator.radius, 15);
        expect(indicator.color, DarkColors.whiteColor);
        expect(indicator.animating, true);
        expect(
          tester.getSize(find.byType(TravibeLoadingIndicator)),
          Size.square(size),
        );
        expect(
          tester.getCenter(find.byType(CupertinoActivityIndicator)),
          tester.getCenter(find.byType(TravibeLoadingIndicator)),
        );
        expect(find.bySemanticsLabel('Loading'), findsOneWidget);
        expect(find.byType(SvgPicture), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await tester.pumpWidget(const SizedBox());
        semantics.dispose();
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull);
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
  }
  testWidgets(
    'an explicit color overrides white and reduced motion is respected',
    (tester) async {
      await show(tester, motion: false, color: Colors.teal);
      var indicator = tester.widget<CupertinoActivityIndicator>(
        find.byType(CupertinoActivityIndicator),
      );
      expect(indicator.animating, false);
      expect(indicator.color, Colors.teal);
      await show(tester);
      indicator = tester.widget<CupertinoActivityIndicator>(
        find.byType(CupertinoActivityIndicator),
      );
      expect(indicator.animating, true);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
