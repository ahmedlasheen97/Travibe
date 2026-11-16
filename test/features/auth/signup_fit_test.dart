import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/auth/screens/sign_up_screen.dart';

void main() {
  setUpAll(() async {
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      await (FontLoader('Plus Jakarta Sans')..addFont(
            rootBundle.load('assets/fonts/PlusJakartaSans-$weight.ttf'),
          ))
          .load();
    }
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
  });
  tearDown(() => PreferencesManager().clear());

  for (final (size, scale, keyboard, fits) in const [
    (Size(375, 812), 1.0, false, true),
    (Size(390, 844), 1.0, false, true),
    (Size(430, 932), 1.0, false, true),
    (Size(320, 568), 1.0, false, false),
    (Size(375, 667), 1.0, false, false),
    (Size(390, 844), 2.0, false, false),
    (Size(390, 844), 1.0, true, false),
    (Size(844, 390), 1.0, false, false),
  ]) {
    for (final language in ['en', 'ar']) {
      testWidgets(
        'signup $size $language scale=$scale keyboard=$keyboard fits=$fits',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
          tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            ScreenUtilInit(
              designSize: const Size(390, 844),
              minTextAdapt: true,
              splitScreenMode: true,
              builder: (_, _) => MaterialApp(
                theme: darkTheme,
                locale: Locale(language),
                supportedLocales: const [Locale('en'), Locale('ar')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: const SignUpScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (keyboard) {
            await tester.showKeyboard(find.byType(TextFormField).first);
            tester.view.viewInsets = const FakeViewPadding(bottom: 270);
            await tester.pumpAndSettle();
          }
          final position = tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position;
          if (fits) {
            expect(position.maxScrollExtent, closeTo(0, .01));
            expect(
              find.text('Create\nyour account').hitTestable(),
              findsOneWidget,
            );
            expect(find.byType(Checkbox).hitTestable(), findsOneWidget);
            expect(
              find.text('Already have an account?').hitTestable(),
              findsOneWidget,
            );
          } else {
            expect(position.maxScrollExtent, greaterThan(0));
            await tester.ensureVisible(find.text('Login'));
            await tester.pumpAndSettle();
          }
          expect(find.text('Login').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
