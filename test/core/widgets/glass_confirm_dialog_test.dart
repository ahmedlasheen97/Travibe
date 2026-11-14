import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/glass_confirm_dialog.dart';
import 'package:travibe/core/widgets/glass_surface.dart';

void main() {
  Future<Future<bool>> open(WidgetTester tester) async {
    late Future<bool> result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => result = showGlassConfirmDialog(
              context,
              title: 'Delete comment?',
              message: 'Gone for good.',
              confirmLabel: 'Delete',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  Color? colorOf(WidgetTester tester, String label) => tester
      .widget<RichText>(
        find.descendant(of: find.text(label), matching: find.byType(RichText)),
      )
      .text
      .style!
      .color;

  double? fontSizeOf(WidgetTester tester, String label) => tester
      .widget<RichText>(
        find.descendant(of: find.text(label), matching: find.byType(RichText)),
      )
      .text
      .style!
      .fontSize;

  testWidgets(
    'uses the Log Out glass look: confirm left in red, Cancel right',
    (tester) async {
      await open(tester);
      expect(
        find.descendant(
          of: find.byType(GlassConfirmDialog),
          matching: find.byType(GlassSurface),
        ),
        findsOneWidget,
      );
      final title = tester.widget<Text>(find.text('Delete comment?'));
      expect(title.style!.fontSize, 18);
      expect(title.style!.fontWeight, FontWeight.w600);
      expect(
        tester.getCenter(find.text('Delete')).dx,
        lessThan(tester.getCenter(find.text('Cancel')).dx),
      );
      expect(colorOf(tester, 'Delete'), DarkColors.dangerColor);
      expect(DarkColors.dangerColor, const Color(0xFFDD312A));
      expect(colorOf(tester, 'Cancel'), DarkColors.whiteColor);
      expect(fontSizeOf(tester, 'Delete'), 18);
      expect(fontSizeOf(tester, 'Cancel'), 18);
    },
  );

  testWidgets('resolves true on confirm and false on cancel', (tester) async {
    var result = await open(tester);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
    result = await open(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });

  testWidgets('loading shows a spinner, disables buttons and shows errors', (
    tester,
  ) async {
    var confirms = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: GlassConfirmDialog(
          title: 'Log Out?',
          message: 'Sure?',
          confirmLabel: 'Log Out',
          loading: true,
          error: 'Something failed',
          onConfirm: () => confirms++,
        ),
      ),
    );
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(find.text('Log Out'), findsNothing);
    expect(find.text('Something failed'), findsOneWidget);
    final buttons = tester.widgetList<TextButton>(find.byType(TextButton));
    expect(buttons.every((b) => b.onPressed == null), isTrue);
    expect(confirms, 0);
  });
}
