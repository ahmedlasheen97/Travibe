import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/custom_button.dart';
import 'package:travibe/features/profile/widgets/profile_action_buttons.dart';
import 'package:travibe/features/auth/widgets/social_login_button.dart';
import 'package:travibe/features/follow/widgets/follow_action_builder.dart';
import 'package:travibe/features/follow/widgets/follow_pill.dart';

void main() {
  setUpAll(() async {
    ScreenUtil.configure(
      data: const MediaQueryData(size: Size(390, 844)),
      designSize: const Size(390, 844),
      minTextAdapt: false,
      splitScreenMode: false,
    );
    final fonts = FontLoader('Plus Jakarta Sans')
      ..addFont(rootBundle.load('assets/fonts/PlusJakartaSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/PlusJakartaSans-SemiBold.ttf'));
    await fonts.load();
  });
  void check(
    WidgetTester tester,
    Finder finder, {
    FontWeight weight = FontWeight.w600,
  }) {
    final button = tester.widget<ButtonStyleButton>(finder);
    final shape = button.style!.shape!.resolve({})! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(32));
    final rich = tester.widget<RichText>(
      find.descendant(of: finder, matching: find.byType(RichText)),
    );
    expect(rich.text.style!.fontSize, 18);
    expect(rich.text.style!.fontWeight, weight);
    expect(rich.text.style!.fontFamily, 'Plus Jakarta Sans');
  }

  for (final outlined in [false, true]) {
    testWidgets(
      'standard ${outlined ? 'secondary' : 'primary'} action has radius 32, label 18 and unchanged height/callback',
      (tester) async {
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: darkTheme,
            home: Scaffold(
              body: CustomButton(
                title: 'Action',
                isOutlined: outlined,
                onPressed: () => taps++,
              ),
            ),
          ),
        );
        final button = find.byType(outlined ? OutlinedButton : ElevatedButton);
        check(tester, button);
        expect(tester.getSize(button).height, 48);
        if (!outlined) {
          expect(
            tester
                .widget<ElevatedButton>(button)
                .style!
                .backgroundColor!
                .resolve({}),
            DarkColors.primaryColor,
          );
        }
        await tester.tap(button);
        expect(taps, 1);
      },
    );
  }
  testWidgets(
    'disabled loading label remains visible at 18 with no submission',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: const Scaffold(
            body: CustomButton(title: 'Logging in...', onPressed: null),
          ),
        ),
      );
      final button = find.byType(ElevatedButton);
      check(tester, button);
      expect(tester.widget<ElevatedButton>(button).onPressed, isNull);
      expect(find.text('Logging in...'), findsOneWidget);
      expect(tester.getSize(button).height, 48);
      await tester.tap(button);
      expect(tester.takeException(), isNull);
    },
  );
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'Profile labels stay at nominal 18 inside 44px actions on a 320px screen at scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var edits = 0;
        final shares = <Rect>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: darkTheme,
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: ProfileActionButtons(
                  onEdit: () => edits++,
                  onShare: shares.add,
                ),
              ),
            ),
          ),
        );
        for (final title in ['Share Profile', 'Edit Profile']) {
          final button = find.widgetWithText(FilledButton, title);
          check(tester, button);
          expect(tester.getSize(button).height, 44);
          final box = tester.renderObject<RenderBox>(
            find.descendant(of: button, matching: find.byType(RichText)),
          );
          final painted = MatrixUtils.transformRect(
            box.getTransformTo(null),
            Offset.zero & box.size,
          );
          final bounds = tester.getRect(button).inflate(.1);
          expect(bounds.contains(painted.topLeft), true);
          expect(bounds.contains(painted.bottomRight), true);
          expect(
            tester
                .widget<FilledButton>(button)
                .style!
                .backgroundColor!
                .resolve({}),
            DarkColors.darkgreyColor,
          );
        }
        await tester.tap(find.widgetWithText(FilledButton, 'Share Profile'));
        expect(shares.single.width, greaterThan(0));
        await tester.tap(find.widgetWithText(FilledButton, 'Edit Profile'));
        expect(edits, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'social secondary actions fit a narrow row without changing 50px height or colors',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  SocialLoginButton(
                    title: 'Google',
                    iconPath: 'assets/images/auth/google.svg',
                    onPressed: () {},
                  ),
                  const SizedBox(width: 16),
                  const SocialLoginButton(
                    title: 'Apple',
                    iconPath: 'assets/images/auth/apple.svg',
                    onPressed: null,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      for (final button in find.byType(ElevatedButton).evaluate()) {
        final finder = find.byWidget(button.widget);
        check(tester, finder, weight: FontWeight.w500);
        expect(tester.getSize(finder).height, 50);
        expect(
          (button.widget as ElevatedButton).style!.backgroundColor!.resolve({}),
          const Color(0xFF303030),
        );
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'compact follow controls keep their established font and stadium shape',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: Scaffold(
            body: FollowPill(
              relation: FollowRelation.follow,
              pending: false,
              onPressed: () {},
            ),
          ),
        ),
      );
      final button = tester.widget<TextButton>(find.byType(TextButton));
      expect(button.style!.shape!.resolve({}), isA<StadiumBorder>());
      expect(tester.widget<Text>(find.text('Follow')).style!.fontSize, 14);
    },
  );
}
