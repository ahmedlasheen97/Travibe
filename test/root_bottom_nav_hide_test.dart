import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/navigation/bottom_nav_visibility.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/buddies/screens/buddies_screen.dart';
import 'package:travibe/features/create_post/cubit/post_upload_cubit.dart';
import 'package:travibe/features/create_post/data/create_post_request.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/root.dart';

import 'features/create_post/fixtures.dart';
import 'features/home/home_experience_fixtures.dart';

const _height = 400.0;
const _inset = 34.0;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
  });
  tearDown(() async => PreferencesManager().clear());

  late MemoryCreatePostRepo createRepo;

  Future<void> pumpRoot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, _height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final account = AccountRepo();
    createRepo = MemoryCreatePostRepo();
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(390, _height),
              padding: EdgeInsets.only(bottom: _inset),
              viewPadding: EdgeInsets.only(bottom: _inset),
            ),
            child: Root(
              homeAccountRepo: account,
              followRepo: PeopleRepo(account),
              postsRepo: EmptyPostsRepo(),
              createPostRepo: createRepo,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
  }

  Finder bar() => find.byType(BottomNavigationBar);
  Finder glass() => find.byKey(const ValueKey('liquid-glass-navigation'));
  BottomNavVisibility nav(WidgetTester tester) => tester
      .widget<HideableBottomBar>(find.byType(HideableBottomBar))
      .visibility;
  // First pump starts the slide; the second runs it to completion.
  Future<void> settleSlide(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(
      BottomNavVisibility.duration + const Duration(milliseconds: 50),
    );
  }

  Future<Finder> openBuddies(WidgetTester tester) async {
    await tester.tap(
      find.descendant(of: bar(), matching: find.text('Buddies')),
    );
    await tester.pumpAndSettle();
    return find
        .descendant(
          of: find.byType(BuddiesScreen),
          matching: find.byType(Scrollable),
        )
        .first;
  }

  testWidgets('content extends under the bar to the screen bottom', (
    tester,
  ) async {
    await pumpRoot(tester);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).extendBody,
      isTrue,
    );
    expect(tester.getRect(find.byType(IndexedStack)).bottom, _height);
    expect(tester.getRect(glass()).bottom, _height);
    expect(tester.takeException(), isNull);
  });

  testWidgets('drag down hides, small drag up shows, reaching top shows', (
    tester,
  ) async {
    await pumpRoot(tester);
    final scrollable = await openBuddies(tester);
    await tester.drag(scrollable, const Offset(0, -120));
    await settleSlide(tester);
    expect(nav(tester).visible, isFalse);
    expect(tester.getRect(glass()).top, greaterThanOrEqualTo(_height));
    // Content still fills the whole screen while the bar is away.
    expect(tester.getRect(find.byType(IndexedStack)).bottom, _height);

    await tester.drag(scrollable, const Offset(0, 30));
    await settleSlide(tester);
    expect(nav(tester).visible, isTrue);
    expect(tester.getRect(glass()).bottom, _height);

    await tester.drag(scrollable, const Offset(0, -120));
    await settleSlide(tester);
    expect(nav(tester).visible, isFalse);
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await settleSlide(tester);
    expect(nav(tester).visible, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching tabs and re-tapping the active tab show the bar', (
    tester,
  ) async {
    await pumpRoot(tester);
    final onTap = tester.widget<BottomNavigationBar>(bar()).onTap!;
    nav(tester).hide();
    await settleSlide(tester);
    onTap(3);
    await settleSlide(tester);
    expect(nav(tester).visible, isTrue);
    expect(tester.widget<BottomNavigationBar>(bar()).currentIndex, 3);

    nav(tester).hide();
    await settleSlide(tester);
    tester.widget<BottomNavigationBar>(bar()).onTap!(3);
    await settleSlide(tester);
    expect(nav(tester).visible, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrollable lists reserve the bar height at the bottom', (
    tester,
  ) async {
    await pumpRoot(tester);
    final reserved = tester
        .widget<BottomNavScope>(find.byType(BottomNavScope))
        .barHeight;
    // Theme height (AppSizes.h95) with >=64px controls above the 34px inset.
    expect(reserved, 64 + _inset);
    await openBuddies(tester);
    final scroll = tester.widget<SingleChildScrollView>(
      find
          .descendant(
            of: find.byType(BuddiesScreen),
            matching: find.byType(SingleChildScrollView),
          )
          .first,
    );
    expect((scroll.padding! as EdgeInsets).bottom, 36 + reserved);
    expect(tester.takeException(), isNull);
  });

  testWidgets('floating SnackBars sit above the bar and drop when hidden', (
    tester,
  ) async {
    await pumpRoot(tester);
    ScaffoldMessenger.of(tester.element(bar())).showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: Duration(minutes: 1),
        content: Text('hello'),
      ),
    );
    await tester.pumpAndSettle();
    final shown = tester.getRect(find.byType(SnackBar)).bottom;
    expect(shown, lessThanOrEqualTo(tester.getRect(glass()).top));
    nav(tester).hide();
    await tester.pumpAndSettle();
    final hidden = tester.getRect(find.byType(SnackBar)).bottom;
    expect(hidden, greaterThan(shown));
    expect(hidden, lessThanOrEqualTo(_height - _inset));
    expect(tester.takeException(), isNull);
  });

  testWidgets('upload toast follows the bar', (tester) async {
    await pumpRoot(tester);
    createRepo.gate = Completer<PostModel>();
    tester
        .element(bar())
        .read<PostUploadCubit>()
        .enqueue(const CreatePostRequest(content: 'Hello'));
    await tester.pump(const Duration(milliseconds: 300));
    final toast = find.byKey(const ValueKey('post-upload-progress'));
    final shown = tester.getRect(toast).bottom;
    expect(shown, lessThanOrEqualTo(tester.getRect(glass()).top));
    nav(tester).hide();
    await settleSlide(tester);
    final hidden = tester.getRect(toast).bottom;
    expect(hidden, greaterThan(shown));
    expect(hidden, lessThanOrEqualTo(_height - _inset));
    nav(tester).show();
    await settleSlide(tester);
    expect(tester.getRect(toast).bottom, shown);
    createRepo.gate!.complete(PostModel.fromJson(postJson()));
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });
}
