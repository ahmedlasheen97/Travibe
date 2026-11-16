import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/custom_text_field.dart';

void main() {
  Future<void> show(WidgetTester tester, Widget field) => tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, _) => MaterialApp(
        theme: darkTheme,
        home: Scaffold(body: field),
      ),
    ),
  );

  void expectDangerError(WidgetTester tester, {required bool focused}) {
    final decorator = tester.widget<InputDecorator>(
      find.byType(InputDecorator),
    );
    expect(decorator.isFocused, focused);
    final decoration = decorator.decoration.applyDefaults(
      darkTheme.inputDecorationTheme,
    );
    final normal = decoration.enabledBorder!.borderSide;
    for (final border in [
      decoration.errorBorder!,
      decoration.focusedErrorBorder!,
    ]) {
      expect(border.borderSide.color, DarkColors.dangerColor);
      expect(DarkColors.dangerColor, const Color(0xFFDD312A));
      expect(border.borderSide.width, normal.width);
    }
    expect(
      tester.widget<Text>(find.text('Required')).style!.color,
      DarkColors.dangerColor,
    );
  }

  testWidgets('shared text field error is danger red, focused or not', (
    tester,
  ) async {
    await show(
      tester,
      const CustomTextField(title: '', hintText: 'name', errorText: 'Required'),
    );
    expectDangerError(tester, focused: false);
    await tester.tap(find.byType(TextFormField));
    await tester.pump();
    expectDangerError(tester, focused: true);
  });

  testWidgets('plain themed fields (settings forms) share the same error', (
    tester,
  ) async {
    await show(
      tester,
      const TextField(decoration: InputDecoration(errorText: 'Required')),
    );
    expectDangerError(tester, focused: false);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expectDangerError(tester, focused: true);
  });
}
