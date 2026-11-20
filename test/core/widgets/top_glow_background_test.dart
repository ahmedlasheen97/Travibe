import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/top_glow_background.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/buddies/screens/buddies_screen.dart';
import 'package:travibe/features/explore/screens/explore_screen.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/home/data/home_account_repo.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/home/screens/home_screen.dart';
import 'package:travibe/features/home/widgets/home_user_avatar.dart';
import 'package:travibe/features/home/widgets/pinned_tabs_delegate.dart';
import 'package:travibe/features/profile/screens/profile_screen.dart';

import '../../features/home/home_experience_fixtures.dart';
import '../../features/profile/fixtures.dart';
import '../../helpers/fake_network_images.dart';

class _AvatarAccount extends AccountRepo {
  @override
  Future<HomeAccount> getAccount() async => const HomeAccount(
    id: '1',
    name: 'Viewer',
    avatarUrl: 'https://example.invalid/me.png',
    followingCount: 0,
  );
}

PostModel _postBy(int authorId) => PostModel.fromJson({
  'id': 50 + authorId,
  'type': 'text',
  'user_id': authorId,
  'user': {
    'id': authorId,
    'name': 'ahmed lasheen$authorId',
    'username': 'a$authorId',
    'avatar_url': 'https://example.invalid/author$authorId.png',
  },
  'content': 'Post by $authorId',
  'visibility': 'public',
  'media': [],
});

RenderTopGlowBackdrop _backdrop(WidgetTester tester, Finder finder) =>
    tester.renderObject<RenderTopGlowBackdrop>(finder);

final _glow = find.byKey(TopGlowBackground.glowKey);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 390,
  double height = 844,
  bool settle = true,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, _) => MaterialApp(theme: darkTheme, home: child),
    ),
  );
  // Explore's illustration floats forever, so it can't settle.
  settle
      ? await tester.pumpAndSettle()
      : await tester.pump(const Duration(milliseconds: 100));
}

Rect _glowRect(WidgetTester tester) => tester.getRect(_glow);

/// The scroll fade of the (first) TopGlowBackground on screen.
double _opacity(WidgetTester tester) {
  final background = tester.widget<TopGlowBackground>(
    find.byType(TopGlowBackground).first,
  );
  final content = find.byWidgetPredicate((w) => identical(w, background.child));
  return TopGlowBackground.opacityOf(tester.element(content.first))!.value;
}

/// Scrolling the screen's own vertical scroll view fades the glow out by
/// 120 px and back in at the top (the glow stays fixed, never re-blurred).
Future<void> _expectFadesOnScroll(WidgetTester tester) async {
  final scrollable = find.byWidgetPredicate(
    (w) =>
        w is Scrollable &&
        axisDirectionToAxis(w.axisDirection) == Axis.vertical,
  );
  final position = tester.state<ScrollableState>(scrollable.first).position;
  expect(position.maxScrollExtent, greaterThanOrEqualTo(120));
  final glow = _glowRect(tester);
  position.jumpTo(0);
  await tester.pump();
  expect(_opacity(tester), 1);
  position.jumpTo(60);
  await tester.pump();
  expect(_opacity(tester), closeTo(0.5, 1e-9));
  position.jumpTo(120);
  await tester.pump();
  expect(_opacity(tester), 0);
  position.jumpTo(0);
  await tester.pump();
  expect(_opacity(tester), 1);
  expect(_glowRect(tester), glow);
}

/// The glow is present at the screen's top-left and doesn't move when the
/// screen's content is dragged up.
Future<void> _expectFixedGlow(WidgetTester tester) async {
  expect(_glow, findsOneWidget);
  final before = _glowRect(tester);
  expect(before.topLeft, Offset.zero);
  final gesture = await tester.startGesture(const Offset(200, 500));
  await gesture.moveBy(const Offset(0, -200));
  await tester.pump();
  expect(_glowRect(tester), before);
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 500));
  expect(_glowRect(tester), before);
}

void main() {
  group('TopGlowBackground', () {
    for (final width in [390.0, 430.0]) {
      testWidgets('frame and circle scale with width $width', (tester) async {
        await _pump(
          tester,
          const TopGlowBackground(child: SizedBox.expand()),
          width: width,
        );
        final s = width / 390;
        expect(_glowRect(tester), Rect.fromLTWH(0, 0, 390 * s, 391 * s));
        final g = TopGlowGeometry.forWidth(width);
        expect(g.circle, Rect.fromLTWH(-25 * s, -91 * s, 182 * s, 182 * s));
        expect(g.sigma, closeTo(150 * 0.9 * s, 1e-9));
      });
    }

    testWidgets('stays fixed while content scrolls over it', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      const content = ValueKey('content');
      await _pump(
        tester,
        TopGlowBackground(
          child: ListView(
            controller: controller,
            children: const [
              SizedBox(key: content, height: 400),
              SizedBox(height: 3000),
            ],
          ),
        ),
      );
      final fixed = _glowRect(tester);
      expect(fixed.topLeft, Offset.zero);

      // A real drag, mid-gesture and after the fling settles.
      final gesture = await tester.startGesture(const Offset(200, 500));
      await gesture.moveBy(const Offset(0, -150));
      await tester.pump();
      expect(controller.offset, greaterThan(0));
      expect(tester.getTopLeft(find.byKey(content)).dy, lessThan(0));
      expect(_glowRect(tester), fixed);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_glowRect(tester), fixed);

      controller.jumpTo(1200);
      await tester.pump();
      expect(_glowRect(tester), fixed);
    });

    testWidgets('content paints over the glow and receives taps', (
      tester,
    ) async {
      var taps = 0;
      await _pump(
        tester,
        TopGlowBackground(
          child: Align(
            alignment: Alignment.topLeft,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              child: const SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      );
      final stack = tester.widget<Stack>(
        find
            .descendant(
              of: find.byType(TopGlowBackground),
              matching: find.byType(Stack),
            )
            .first,
      );
      // Glow first (bottom), content last (top).
      expect(
        find.descendant(
          of: find.byWidget(stack.children.first),
          matching: _glow,
        ),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(50, 50));
      expect(taps, 1);
    });

    testWidgets('blur is rasterized once across rebuilds and scrolling', (
      tester,
    ) async {
      // A width no other test uses, so this starts with an empty cache entry.
      final before = TopGlowRaster.debugRasterCount;
      final controller = ScrollController();
      addTearDown(controller.dispose);
      Widget app(Color color) => TopGlowBackground(
        color: color,
        child: ListView(
          controller: controller,
          children: const [SizedBox(height: 3000)],
        ),
      );
      await _pump(tester, app(Colors.black), width: 411);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(home: app(Colors.black87)),
        ),
      );
      for (var i = 1; i <= 5; i++) {
        controller.jumpTo(i * 40);
        await tester.pump();
      }
      expect(TopGlowRaster.debugRasterCount - before, 1);
    });
  });

  group('scroll fade', () {
    Future<ScrollController> pumpList(
      WidgetTester tester, {
      bool fade = true,
      Widget? header,
      void Function()? onBuild,
    }) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        TopGlowBackground(
          fadeOnScroll: fade,
          child: Builder(
            builder: (context) {
              onBuild?.call();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ?header,
                  Expanded(
                    child: ListView(
                      controller: controller,
                      physics: const BouncingScrollPhysics(),
                      children: [
                        SizedBox(
                          height: 120,
                          child: ListView(
                            key: const ValueKey('horizontal'),
                            scrollDirection: Axis.horizontal,
                            children: const [SizedBox(width: 3000)],
                          ),
                        ),
                        const SizedBox(height: 3000),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
      return controller;
    }

    testWidgets('fades out by 120 px and back in at the top, repaint only', (
      tester,
    ) async {
      var builds = 0;
      final rasters = TopGlowRaster.debugRasterCount;
      final controller = await pumpList(tester, onBuild: () => builds++);
      final built = builds;
      final glow = _glowRect(tester);
      expect(_opacity(tester), 1);
      expect(tester.renderObject(_glow), paints..drawImageRect());

      controller.jumpTo(60);
      await tester.pump();
      expect(_opacity(tester), closeTo(0.5, 1e-9));
      controller.jumpTo(120);
      await tester.pump();
      expect(_opacity(tester), 0);
      // Fully hidden: the glow layer paints nothing.
      expect(tester.renderObject(_glow), isNot(paints..drawImageRect()));
      controller.jumpTo(800);
      await tester.pump();
      expect(_opacity(tester), 0);

      controller.jumpTo(30);
      await tester.pump();
      expect(_opacity(tester), closeTo(0.75, 1e-9));
      controller.jumpTo(0);
      await tester.pump();
      expect(_opacity(tester), 1);

      expect(builds, built, reason: 'scrolling must not rebuild');
      expect(TopGlowRaster.debugRasterCount, rasters);
      expect(_glowRect(tester), glow);
    });

    testWidgets('horizontal scrolling and pull overscroll keep full glow', (
      tester,
    ) async {
      await pumpList(tester);
      await tester.drag(
        find.byKey(const ValueKey('horizontal')),
        const Offset(-300, 0),
      );
      await tester.pump();
      expect(_opacity(tester), 1);
      final gesture = await tester.startGesture(const Offset(200, 400));
      await gesture.moveBy(const Offset(0, 200));
      await tester.pump();
      expect(_opacity(tester), 1);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_opacity(tester), 1);
    });

    testWidgets('pinned backdrop copies fade with the glow', (tester) async {
      const key = ValueKey('pinned');
      final controller = await pumpList(
        tester,
        header: const TopGlowBackdrop(key: key, child: SizedBox(height: 40)),
      );
      final backdrop = _backdrop(tester, find.byKey(key));
      expect(backdrop.glowOpacity, 1);
      controller.jumpTo(90);
      await tester.pump();
      expect(backdrop.glowOpacity, closeTo(0.25, 1e-9));
      expect(backdrop.glowOpacity, _opacity(tester));
      controller.jumpTo(0);
      await tester.pump();
      expect(backdrop.glowOpacity, 1);
    });

    testWidgets('without fadeOnScroll the glow never fades', (tester) async {
      final controller = await pumpList(tester, fade: false);
      controller.jumpTo(500);
      await tester.pump();
      expect(_opacity(tester), 1);
    });
  });

  group('TopGlowBackdrop', () {
    testWidgets('paints the page color and the glow aligned to the fixed one', (
      tester,
    ) async {
      const key = ValueKey('backdrop');
      await _pump(
        tester,
        const TopGlowBackground(
          color: Color(0xFF0A0A0A),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 100),
              TopGlowBackdrop(key: key, child: SizedBox(height: 50)),
            ],
          ),
        ),
      );
      final backdrop = _backdrop(tester, find.byKey(key));
      // The glow frame starts 100px above this box.
      expect(backdrop.glowOffset, const Offset(0, -100));
      expect(
        backdrop,
        paints
          ..rect(color: const Color(0xFF0A0A0A))
          ..drawImageRect(destination: const Rect.fromLTWH(0, -100, 390, 391)),
      );
    });

    testWidgets('pinned header fade appears only once the header pins', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        TopGlowBackground(
          child: CustomScrollView(
            controller: controller,
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 200)),
              SliverPersistentHeader(
                pinned: true,
                delegate: PinnedTabsDelegate(
                  height: 50,
                  child: const Text('Tabs'),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 3000)),
            ],
          ),
        ),
      );
      final header = find.byKey(const ValueKey('home-tabs-backdrop'));
      // At rest it doesn't dim the first post.
      expect(_backdrop(tester, header).fadeStrength, 0);
      controller.jumpTo(600);
      await tester.pump();
      expect(tester.getTopLeft(header).dy, 0);
      expect(_backdrop(tester, header).fadeStrength, 1);
      // Same glow as the fixed one, offset by the header's place on screen.
      expect(_backdrop(tester, header).glowOffset, Offset.zero);
      expect(_glowRect(tester).topLeft, Offset.zero);
    });

    testWidgets('without a TopGlowBackground it falls back to a solid color', (
      tester,
    ) async {
      const key = ValueKey('lone-backdrop');
      await _pump(
        tester,
        const TopGlowBackdrop(key: key, child: SizedBox(height: 40)),
      );
      final backdrop = _backdrop(tester, find.byKey(key));
      expect(backdrop.glowOffset, isNull);
      expect(backdrop, paints..rect(color: darkTheme.scaffoldBackgroundColor));
      expect(backdrop, isNot(paints..drawImageRect()));
    });
  });

  group('screens show the top glow', () {
    late FollowCubit follow;
    late BlockCubit block;
    setUp(() {
      follow = FollowCubit(repo: PeopleRepo(AccountRepo()));
      block = BlockCubit(follow: follow);
    });
    tearDown(() async {
      await block.close();
      await follow.close();
    });

    Widget withCubits(Widget child) => MultiBlocProvider(
      providers: [
        BlocProvider.value(value: follow),
        BlocProvider.value(value: block),
      ],
      child: child,
    );

    testWidgets('Home', (tester) async {
      await _pump(
        tester,
        Scaffold(
          body: withCubits(
            HomeScreen(accountRepo: AccountRepo(), postsRepo: EmptyPostsRepo()),
          ),
        ),
      );
      await _expectFixedGlow(tester);
    });

    testWidgets('own Profile', (tester) async {
      await _pump(
        tester,
        ProfileScreen(
          profileRepo: MemoryProfileRepo(),
          postsRepo: EmptyProfilePostsRepo(),
        ),
      );
      await _expectFixedGlow(tester);
    });

    testWidgets('other user Profile', (tester) async {
      await _pump(
        tester,
        withCubits(
          ProfileScreen(
            userId: 23,
            profileRepo: MemoryProfileRepo(),
            postsRepo: EmptyProfilePostsRepo(),
          ),
        ),
      );
      await _expectFixedGlow(tester);
      // The app bar stays see-through so the glow shows behind it.
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, Colors.transparent);
    });

    testWidgets('Buddies', (tester) async {
      await _pump(tester, const BuddiesLandingView());
      await _expectFixedGlow(tester);
    });

    testWidgets('Explore', (tester) async {
      await _pump(tester, const ExploreScreen(), settle: false);
      await _expectFixedGlow(tester);
      // Explore doesn't scroll and never fades.
      expect(_opacity(tester), 1);
    });

    // A short viewport so the fixture content scrolls past 120 px.
    for (final (name, screen) in <(String, Widget Function())>[
      (
        'Home',
        () => Scaffold(
          body: withCubits(
            HomeScreen(accountRepo: AccountRepo(), postsRepo: EmptyPostsRepo()),
          ),
        ),
      ),
      (
        'own Profile',
        () => ProfileScreen(
          profileRepo: MemoryProfileRepo(),
          postsRepo: EmptyProfilePostsRepo(),
        ),
      ),
      ('Buddies', () => const BuddiesLandingView()),
    ]) {
      testWidgets('$name glow fades out on scroll and back in at the top', (
        tester,
      ) async {
        await _pump(tester, screen(), height: 360);
        await _expectFadesOnScroll(tester);
      });
    }

    testWidgets('Home pinned tabs use the glow backdrop, not a solid band', (
      tester,
    ) async {
      await _pump(
        tester,
        Scaffold(
          body: withCubits(
            HomeScreen(accountRepo: AccountRepo(), postsRepo: EmptyPostsRepo()),
          ),
        ),
      );
      final header = find.byKey(const ValueKey('home-tabs-backdrop'));
      expect(header, findsOneWidget);
      expect(_backdrop(tester, header).glowOffset, isNotNull);
      expect(
        find.ancestor(
          of: find.text('For You'),
          matching: find.byWidgetPredicate(
            (w) => w is Container && w.color != null,
          ),
        ),
        findsNothing,
      );
    });

    for (final (name, screen) in [
      (
        'own Profile',
        () => ProfileScreen(
          profileRepo: MemoryProfileRepo(),
          postsRepo: EmptyProfilePostsRepo(),
        ),
      ),
      ('Buddies', () => const BuddiesLandingView()),
    ]) {
      testWidgets('$name content fades at the top edge over the glow', (
        tester,
      ) async {
        await _pump(tester, screen());
        final fade = find.byKey(TopGlowEdgeFade.fadeKey);
        expect(fade, findsOneWidget);
        expect(_backdrop(tester, fade).fadeStrength, 1);
        expect(_backdrop(tester, fade).glowOffset, isNotNull);
      });
    }

    testWidgets('Home avatars render with the glow ("You" and post author)', (
      tester,
    ) async {
      // "You" uses the account picture only for a signed-in session.
      SharedPreferences.setMockInitialValues({});
      await PreferencesManager().init();
      await PreferencesManager().saveToken('glow-avatars');
      final posts = EmptyPostsRepo()..explorePosts = [_postBy(2)];
      await withFakeNetworkImages(() async {
        await _pump(
          tester,
          Scaffold(
            body: withCubits(
              HomeScreen(accountRepo: _AvatarAccount(), postsRepo: posts),
            ),
          ),
        );
        // Let the (fake) HTTP responses and image decoding complete.
        for (var i = 0; i < 5; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
        }
      });
      expect(_glow, findsOneWidget);

      final you = find.byKey(const ValueKey('story-avatar-you'));
      expect(you, findsOneWidget);
      final picture = tester.widget<RawImage>(
        find.descendant(of: you, matching: find.byType(RawImage)),
      );
      expect(picture.image, isNotNull, reason: '"You" shows the photo');

      final author = find.byKey(const ValueKey('post-author-avatar'));
      expect(author, findsOneWidget);
      final avatar = tester.widget<CircleAvatar>(author);
      expect(
        (avatar.foregroundImage! as NetworkImage).url,
        'https://example.invalid/author2.png',
      );
      expect(author, paints..drawImageRect());

      // Avatars sit above the glow: taps reach them, not the glow layer.
      for (final finder in [you, author]) {
        final hits = tester.hitTestOnBinding(tester.getCenter(finder));
        expect(
          hits.path.any((e) => e.target == tester.renderObject(finder.first)),
          isTrue,
        );
      }
    });

    testWidgets('avatars show a placeholder, never a hole, while loading', (
      tester,
    ) async {
      // No fake HTTP: the image never arrives in this test.
      await _pump(
        tester,
        const TopGlowBackground(
          child: Center(
            child: HomeUserAvatar(url: 'https://example.invalid/slow.png'),
          ),
        ),
        settle: false,
      );
      expect(
        find.descendant(
          of: find.byType(HomeUserAvatar),
          matching: find.byWidgetPredicate(
            (w) => w is ColoredBox && w.color == const Color(0xFF2A2A2A),
          ),
        ),
        findsOneWidget,
      );
    });
  });
}
