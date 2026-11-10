import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:travibe/core/widgets/glass_surface.dart';

void main() {
  testWidgets(
    'glass Back clips blur, shows white directional SVG, and calls override once',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(body: BackButtonWidget(onTap: () => taps++)),
        ),
      );
      expect(find.byType(GlassSurface), findsOneWidget);
      expect(find.byType(ClipRRect), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
      final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(
        (svg.bytesLoader as SvgAssetLoader).assetName,
        'assets/images/home/arrow-left.svg',
      );
      expect(svg.matchTextDirection, true);
      expect(
        svg.colorFilter,
        const ColorFilter.mode(Colors.white, BlendMode.srcIn),
      );
      final decoration =
          tester
                  .widget<DecoratedBox>(
                    find.descendant(
                      of: find.byType(GlassSurface),
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect(decoration.color!.a, lessThan(1));
      expect(decoration.border, isNotNull);
      expect(tester.getSize(find.byType(BackButtonWidget)), const Size(44, 44));
      await tester.tap(find.byTooltip('Back'));
      expect(taps, 1);
    },
  );
  testWidgets('disabled Back cannot invoke callback', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BackButtonWidget(enabled: false, onTap: () => taps++),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Back'));
    expect(taps, 0);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
  });
  testWidgets(
    'compact circle keeps header layout and supports high contrast without blur',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(highContrast: true),
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  height: 40,
                  child: BackButtonWidget(size: 36, iconSize: 16, onTap: () {}),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
      expect(tester.getSize(find.byType(GlassSurface)), const Size(36, 36));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'default Back pops an existing route and safely leaves a root route in place',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: BackButtonWidget()),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BackButtonWidget())),
      );
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(BackButtonWidget), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
