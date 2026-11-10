import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/liquid_glass_bottom_nav.dart';
import 'package:travibe/features/buddies/screens/buddies_screen.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/home/screens/home_screen.dart';
import 'package:travibe/root.dart';
import '../../features/home/home_experience_fixtures.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
  });
  tearDown(() async => PreferencesManager().clear());

  Future<void> show(
    WidgetTester tester, {
    double width = 390,
    double height = 844,
    double bottom = 0,
    double scale = 1,
    double keyboard = 0,
    bool root = false,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final account = AccountRepo();
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, height),
              padding: EdgeInsets.only(bottom: bottom),
              viewPadding: EdgeInsets.only(bottom: bottom),
              viewInsets: EdgeInsets.only(bottom: keyboard),
              textScaler: TextScaler.linear(scale),
            ),
            child: root
                ? Root(
                    homeAccountRepo: account,
                    followRepo: PeopleRepo(account),
                    postsRepo: EmptyPostsRepo(),
                  )
                : const _Harness(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
  }

  Finder bar() => find.byType(BottomNavigationBar);
  Color? labelColor(WidgetTester tester, String label) {
    final text = tester.widget<Text>(find.text(label));
    return text.style?.color ??
        DefaultTextStyle.of(tester.element(find.text(label))).style.color;
  }

  testWidgets(
    'clipped 18px glass stays attached to bottom and preserves five positions',
    (tester) async {
      await show(tester);
      final glass = find.byKey(const ValueKey('liquid-glass-navigation'));
      final rect = tester.getRect(glass);
      expect(rect.left, 0);
      expect(rect.right, 390);
      expect(rect.bottom, 844);
      final blur = find.descendant(
        of: glass,
        matching: find.byType(BackdropFilter),
      );
      expect(blur, findsOneWidget);
      expect(
        tester.widget<BackdropFilter>(blur).filter.toString(),
        contains('18.0'),
      );
      expect(
        find.ancestor(of: blur, matching: find.byType(ClipRRect)),
        findsWidgets,
      );
      expect(tester.widget<BottomNavigationBar>(bar()).items, hasLength(5));
      for (final label in ['Home', 'Explore', 'Buddies', 'Profile']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(tester.widget<Scaffold>(find.byType(Scaffold)).extendBody, false);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('outer glass remains seamless without individual tab decorations', (
    tester,
  ) async {
    await show(tester, bottom: 34);
    final blur = find.descendant(
      of: find.byKey(const ValueKey('liquid-glass-navigation')),
      matching: find.byType(BackdropFilter),
    );
    final surface = tester.widget<BackdropFilter>(blur).child! as DecoratedBox;
    final decoration = surface.decoration as BoxDecoration;
    expect(decoration.border, isNull);
    expect(decoration.boxShadow, isNull);
    expect(decoration.gradient, isNotNull);
    expect(decoration.color!.a, greaterThan(0));
    expect(decoration.color!.a, lessThan(1));
    // One continuous surface paints behind both controls and the home indicator.
    expect(surface.child, isA<SafeArea>());
    expect(
      tester
          .getRect(find.byKey(const ValueKey('liquid-glass-navigation')))
          .bottom,
      844,
    );
    expect(tester.getRect(bar()).bottom, 810);
    expect(
      find.descendant(of: blur, matching: find.byType(AnimatedContainer)),
      findsNothing,
    );
    expect((surface.child! as SafeArea).child, isA<ConstrainedBox>());
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'selection animates only presentation; center callback preserves current tab',
    (tester) async {
      await show(tester);
      final selected = labelColor(tester, 'Home');
      final unselected = labelColor(tester, 'Explore');
      expect(selected, isNot(unselected));
      await tester.tap(find.text('Explore'));
      await tester.pumpAndSettle();
      expect(tester.widget<BottomNavigationBar>(bar()).currentIndex, 1);
      expect(labelColor(tester, 'Explore'), selected);
      expect(labelColor(tester, 'Home'), unselected);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.text('Center 1'), findsOneWidget);
      expect(tester.widget<BottomNavigationBar>(bar()).currentIndex, 1);
      expect(tester.takeException(), isNull);
    },
  );
  for (final config in [
    (320.0, 34.0, 2.5),
    (390.0, 34.0, 1.0),
    (430.0, 24.0, 2.0),
    (320.0, 0.0, 1.0),
  ]) {
    testWidgets(
      'safe area and labels fit width ${config.$1} inset ${config.$2} scale ${config.$3}',
      (tester) async {
        await show(
          tester,
          width: config.$1,
          bottom: config.$2,
          scale: config.$3,
        );
        expect(
          tester.getRect(bar()).bottom,
          lessThanOrEqualTo(844 - config.$2),
        );
        expect(tester.getSize(bar()).height, greaterThanOrEqualTo(48));
        for (final label in ['Home', 'Explore', 'Buddies', 'Profile']) {
          final target = find
              .ancestor(
                of: find.text(label),
                matching: find.byType(InkResponse),
              )
              .first;
          expect(tester.getSize(target).width, greaterThanOrEqualTo(44));
          expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'keyboard insets do not change navigation selection or callback',
    (tester) async {
      await show(tester, bottom: 34, keyboard: 300);
      await tester.tap(find.text('Buddies'));
      await tester.pumpAndSettle();
      expect(tester.widget<BottomNavigationBar>(bar()).currentIndex, 3);
      expect(tester.getRect(bar()).bottom, lessThanOrEqualTo(810));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('real center SVG fits above the iOS home indicator', (
    tester,
  ) async {
    await show(tester, root: true, bottom: 34);
    expect(tester.getRect(bar()).bottom, lessThanOrEqualTo(810));
    final nav = tester.widget<BottomNavigationBar>(bar());
    for (final index in [0, 1, 3, 4]) {
      expect(nav.items[index].icon, isA<SvgPicture>());
    }
    final center = nav.items[2].icon as Container;
    expect((center.decoration! as BoxDecoration).boxShadow, isNotEmpty);
    expect(center.child, isA<SvgPicture>());
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Root retains Home and Buddies state, scroll position, shared controllers and SVG mappings',
    (tester) async {
      await show(tester, root: true, bottom: 34, height: 400);
      final homeElement = tester.element(find.byType(HomeScreen));
      final follow = tester.element(bar()).read<FollowCubit>();
      var nav = tester.widget<BottomNavigationBar>(bar());
      expect(
        ((nav.items[0].icon as SvgPicture).bytesLoader as SvgAssetLoader)
            .assetName,
        'assets/images/home/home2.svg',
      );
      expect(
        ((nav.items[3].icon as SvgPicture).bytesLoader as SvgAssetLoader)
            .assetName,
        'assets/images/home/profile-2user.svg',
      );
      await tester.tap(
        find.descendant(of: bar(), matching: find.text('Buddies')),
      );
      await tester.pumpAndSettle();
      final buddiesElement = tester.element(find.byType(BuddiesScreen));
      final scrollable = find
          .descendant(
            of: find.byType(BuddiesScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      final scroll = tester.state<ScrollableState>(scrollable).position;
      expect(scroll.maxScrollExtent, greaterThan(0));
      scroll.jumpTo(scroll.maxScrollExtent.clamp(0, 40));
      await tester.pumpAndSettle();
      final offset = scroll.pixels;
      await tester.tap(find.descendant(of: bar(), matching: find.text('Home')));
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(HomeScreen)), same(homeElement));
      expect(tester.element(bar()).read<FollowCubit>(), same(follow));
      await tester.tap(
        find.descendant(of: bar(), matching: find.text('Buddies')),
      );
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(BuddiesScreen)), same(buddiesElement));
      expect(tester.state<ScrollableState>(scrollable).position.pixels, offset);
      nav = tester.widget<BottomNavigationBar>(bar());
      expect(nav.currentIndex, 3);
      expect(
        ((nav.items[3].icon as SvgPicture).bytesLoader as SvgAssetLoader)
            .assetName,
        'assets/images/home/profile-2user2.svg',
      );
      expect(tester.takeException(), isNull);
    },
  );
}

class _Harness extends StatefulWidget {
  const _Harness();
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int selected = 0, center = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Text('Center $center'),
    bottomNavigationBar: LiquidGlassBottomNav(
      navigation: BottomNavigationBar(
        currentIndex: selected,
        backgroundColor: Colors.transparent,
        elevation: 0,
        onTap: (index) => setState(() {
          if (index == 2) {
            center++;
          } else {
            selected = index;
          }
        }),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'Explore'),
          BottomNavigationBarItem(icon: Icon(Icons.add), label: ' '),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Buddies'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    ),
  );
}
