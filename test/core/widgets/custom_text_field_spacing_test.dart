import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/custom_text_field.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
          'Plus Jakarta Sans',
        )..addFont(rootBundle.load('assets/fonts/PlusJakartaSans-Regular.ttf')))
        .load();
  });
  Future<void> show(
    WidgetTester tester,
    TextDirection direction,
    double iconSize, {
    double width = 390,
    double scale = 1,
    bool material3 = true,
    bool prefix = true,
    bool reservePrefixSpace = true,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: ThemeData(
            useMaterial3: material3,
            brightness: Brightness.dark,
            fontFamily: 'Plus Jakarta Sans',
            colorScheme: darkTheme.colorScheme,
            textTheme: darkTheme.textTheme,
            inputDecorationTheme: darkTheme.inputDecorationTheme,
          ),
          home: Directionality(
            textDirection: direction,
            child: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 844),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      CustomTextField(
                        title: '',
                        hintText: 'New hint',
                        reservePrefixSpace: reservePrefixSpace,
                        prefixIcon: prefix
                            ? SvgPicture.asset(
                                'assets/images/auth/sms.svg',
                                key: const ValueKey('new-icon'),
                                width: iconSize,
                                height: iconSize,
                              )
                            : null,
                        suffixIcon: const SizedBox.square(
                          key: ValueKey('new-suffix'),
                          dimension: 48,
                        ),
                      ),
                      // Previous decoration is a geometry baseline, not production code.
                      TextFormField(
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Old hint',
                          hintStyle: const TextStyle(fontSize: 16),
                          prefixIcon: Padding(
                            padding: const EdgeInsets.all(16),
                            child: prefix
                                ? SvgPicture.asset(
                                    'assets/images/auth/sms.svg',
                                    key: const ValueKey('old-icon'),
                                    width: iconSize,
                                    height: iconSize,
                                  )
                                : null,
                          ),
                          suffixIcon: const SizedBox.square(
                            key: ValueKey('old-suffix'),
                            dimension: 48,
                          ),
                          filled: true,
                          fillColor: const Color(0xFF171717),
                          contentPadding: const EdgeInsets.all(16),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final material3 in [true, false]) {
    for (final direction in TextDirection.values) {
      for (final iconSize in [20.0, 24.0]) {
        testWidgets(
          '8px prefix gap preserves $iconSize icon/height/suffix $direction M3=$material3',
          (tester) async {
            await show(tester, direction, iconSize, material3: material3);
            final icon = tester.getRect(find.byKey(const ValueKey('new-icon')));
            final hint = tester.getRect(find.text('New hint'));
            final gap = direction == TextDirection.ltr
                ? hint.left - icon.right
                : icon.left - hint.right;
            expect(gap, closeTo(8, .01));
            expect(icon.size, Size.square(iconSize));
            final fields = find.byType(TextField);
            expect(
              tester.getSize(fields.first).height,
              tester.getSize(fields.last).height,
            );
            final fresh = tester.widget<TextField>(fields.first);
            final old = tester.widget<TextField>(fields.last);
            expect(fresh.style, old.style);
            expect(
              fresh.decoration!.contentPadding,
              old.decoration!.contentPadding,
            );
            expect(fresh.decoration!.fillColor, old.decoration!.fillColor);
            expect(
              tester.getSize(find.byKey(const ValueKey('new-suffix'))),
              tester.getSize(find.byKey(const ValueKey('old-suffix'))),
            );
            final before = tester.getRect(find.byType(EditableText).first);
            expect(
              direction == TextDirection.ltr ? before.left : before.right,
              closeTo(
                direction == TextDirection.ltr ? hint.left : hint.right,
                .01,
              ),
            );
            await tester.enterText(
              find.byType(TextFormField).first,
              direction == TextDirection.rtl ? 'نص' : 'text',
            );
            await tester.pump();
            expect(
              tester.getRect(find.byType(EditableText).first).left,
              closeTo(before.left, .01),
            );
            expect(
              tester.getRect(find.byType(EditableText).first).right,
              closeTo(before.right, .01),
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
  for (final direction in TextDirection.values) {
    testWidgets('no-prefix field keeps its existing geometry $direction', (
      tester,
    ) async {
      await show(tester, direction, 24, prefix: false);
      final fields = find.byType(TextField);
      expect(
        tester.getSize(fields.first).height,
        tester.getSize(fields.last).height,
      );
      final newOffset =
          tester.getRect(find.text('New hint')).left -
          tester.getRect(fields.first).left;
      final oldOffset =
          tester.getRect(find.text('Old hint')).left -
          tester.getRect(fields.last).left;
      expect(newOffset, closeTo(oldOffset, .01));
      await tester.pumpWidget(const SizedBox());
    });
    for (final width in [320.0, 375.0, 393.0, 430.0]) {
      testWidgets('responsive prefix gap at $width with 2x text $direction', (
        tester,
      ) async {
        await show(tester, direction, 24, width: width, scale: 2);
        final icon = tester.getRect(find.byKey(const ValueKey('new-icon')));
        final hint = tester.getRect(find.text('New hint'));
        expect(
          direction == TextDirection.ltr
              ? hint.left - icon.right
              : icon.left - hint.right,
          closeTo(AppSizes.adaptiveWidth(8), .01),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
  for (final direction in TextDirection.values) {
    testWidgets(
      'explicit icon-free inset keeps height and directional text alignment $direction',
      (tester) async {
        await show(
          tester,
          direction,
          24,
          prefix: false,
          reservePrefixSpace: false,
        );
        final fields = find.byType(TextField);
        expect(
          tester.widget<TextField>(fields.first).decoration!.prefixIcon,
          isNull,
        );
        final hint = tester.getRect(find.text('New hint'));
        final input = tester.getRect(fields.first);
        expect(
          direction == TextDirection.ltr
              ? hint.left - input.left
              : input.right - hint.right,
          closeTo(20, .01),
        );
        expect(input.height, tester.getSize(fields.last).height);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
