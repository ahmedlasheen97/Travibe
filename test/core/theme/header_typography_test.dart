import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/profile/widgets/profile_tabs.dart';
import 'package:travibe/features/auth/screens/login_screen.dart';
import 'package:travibe/features/auth/screens/sign_up_screen.dart';

void main() {
  setUpAll(() async {
    final fonts = FontLoader('Plus Jakarta Sans')
      ..addFont(rootBundle.load('assets/fonts/PlusJakartaSans-Regular.ttf'));
    await fonts.load();
  });
  for (final title in ['Login', 'Sign Up']) {
    testWidgets('$title AppBar renders without inherited strikethrough', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            theme: darkTheme,
            home: title == 'Login' ? const LoginScreen() : const SignUpScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final text = find.descendant(
        of: find.byType(AppBar),
        matching: find.text(title),
      );
      final rich = tester.widget<RichText>(
        find.descendant(of: text, matching: find.byType(RichText)),
      );
      expect(rich.text.style!.decoration, TextDecoration.none);
      expect(rich.text.style!.color, Colors.white);
      expect(rich.text.style!.fontFamily, 'Plus Jakarta Sans');
      expect(rich.text.style!.fontSize, 16);
      expect(rich.text.style!.fontWeight, FontWeight.w400);
      expect(tester.getCenter(text).dx, closeTo(195, .01));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'shared AppBar keeps explicit header size/weight and no decoration across route titles',
    (tester) async {
      ScreenUtil.configure(
        data: const MediaQueryData(size: Size(390, 844)),
        designSize: const Size(390, 844),
        minTextAdapt: false,
        splitScreenMode: false,
      );
      for (final title in [
        'Edit Profile',
        'Profile Setup',
        'Followers',
        'Following',
        'Settings',
        'Delete Account',
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: darkTheme,
            home: Scaffold(
              appBar: AppBar(
                title: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        );
        final text = find.text(title);
        final rich = tester.widget<RichText>(
          find.descendant(of: text, matching: find.byType(RichText)),
        );
        expect(rich.text.style!.decoration, TextDecoration.none);
        expect(rich.text.style!.fontSize, 17);
        expect(rich.text.style!.fontWeight, FontWeight.w700);
        expect(rich.text.style!.fontFamily, 'Plus Jakarta Sans');
        expect(
          tester.getCenter(text).dx,
          closeTo(
            tester.view.physicalSize.width / tester.view.devicePixelRatio / 2,
            .01,
          ),
        );
      }
    },
  );
  testWidgets(
    'legitimate profile selection underline remains and follows the selected tab',
    (tester) async {
      ScreenUtil.configure(
        data: const MediaQueryData(size: Size(390, 844)),
        designSize: const Size(390, 844),
        minTextAdapt: false,
        splitScreenMode: false,
      );
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => ProfileTabs(
                selectedIndex: selected,
                onTabSelected: (value) => update(() => selected = value),
              ),
            ),
          ),
        ),
      );
      List<Container> lines() => tester
          .widgetList<Container>(find.byType(Container))
          .where(
            (c) =>
                c.constraints?.maxWidth == 40 && c.constraints?.maxHeight == 2,
          )
          .toList();
      expect(lines(), hasLength(3));
      expect(lines().where((line) => line.color == Colors.white), hasLength(1));
      await tester.tap(find.text('About'));
      await tester.pump();
      expect(selected, 1);
      expect(lines()[1].color, Colors.white);
      expect(lines()[0].color, Colors.transparent);
      expect(tester.takeException(), isNull);
    },
  );
}
