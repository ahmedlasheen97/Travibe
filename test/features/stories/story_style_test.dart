import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/home/widgets/home_stories.dart';
import 'package:travibe/features/profile/screens/settings_screen.dart';
import 'package:travibe/features/profile/widgets/story_style_bottom_sheet.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/data/story_style.dart';
import 'package:travibe/features/stories/widgets/story_ring.dart';
import '../profile/settings_privacy_test.dart' as settings;
import 'story_publishing_test.dart' show groupJson;

/// Paints a 64x80 radius-16 rectangle ring at 4x and returns RGBA bytes.
Future<List<int>> _pixels(List<Color> colors) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(4);
  StoryRingPainter(
    colors: colors,
    cornerRadius: 16,
  ).paint(canvas, const Size(64, 80));
  final picture = recorder.endRecording();
  final raster = await picture.toImage(256, 320);
  try {
    final bytes = await raster.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    return List.of(bytes!.buffer.asUint8List());
  } finally {
    raster.dispose();
    picture.dispose();
  }
}

int _alpha(List<int> pixels, double x, double y) {
  final offset = ((y * 4).floor() * 256 + (x * 4).floor()) * 4;
  return pixels[offset + 3];
}

void main() {
  final preferences = PreferencesManager();
  setUp(() async {
    ScreenUtil.configure(
      data: const MediaQueryData(size: Size(390, 844)),
      designSize: const Size(390, 844),
      minTextAdapt: false,
      splitScreenMode: false,
    );
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.saveToken('story-style');
  });
  tearDown(() => preferences.clear());

  group('rectangle ring painter', () {
    testWidgets('one story draws a continuous 2px rounded-rectangle border', (
      tester,
    ) async {
      final pixels = (await tester.runAsync(
        () => _pixels([DarkColors.primaryColor]),
      ))!;
      // Edges are painted inside the card bounds, 0–2px deep.
      expect(_alpha(pixels, 32, 1), 255);
      expect(_alpha(pixels, 63, 40), 255);
      expect(_alpha(pixels, 32, 79), 255);
      expect(_alpha(pixels, 1, 40), 255);
      // Interior and the clipped-away corners stay transparent.
      expect(_alpha(pixels, 32, 40), 0);
      expect(_alpha(pixels, 4, 4), 0);
      expect(_alpha(pixels, 3.5, 30), 0);
    });

    testWidgets('two stories leave gaps at top-center and bottom-center', (
      tester,
    ) async {
      final pixels = (await tester.runAsync(
        () => _pixels([DarkColors.primaryColor, Colors.white24]),
      ))!;
      expect(_alpha(pixels, 32, 1), 0);
      expect(_alpha(pixels, 32, 79), 0);
      // First (unseen, orange) segment runs clockwise down the right edge,
      // second (seen, grey) up the left.
      final right = ((40 * 4) * 256 + 63 * 4) * 4;
      expect(pixels.sublist(right, right + 4), [228, 92, 16, 255]);
      final left = ((40 * 4) * 256 + 1 * 4) * 4;
      expect(pixels.sublist(left, left + 4), [255, 255, 255, 61]);
    });

    test('circle stays the default and repaints on shape change', () {
      final circle = StoryRingPainter(colors: const [Colors.white24]);
      expect(circle.cornerRadius, isNull);
      expect(
        StoryRingPainter(
          colors: const [Colors.white24],
          cornerRadius: 16,
        ).shouldRepaint(circle),
        isTrue,
      );
    });
  });

  group('HomeStories style', () {
    final own = StoryGroup.fromJson(groupJson(7));
    final other = StoryGroup.fromJson(groupJson(8));

    Future<void> show(WidgetTester tester, StoryStyle? style) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: style == null
                ? HomeStories(
                    stories: [own, other],
                    currentUserId: 7,
                    onAddStory: () {},
                    onViewStory: (_, _) {},
                  )
                : HomeStories(
                    stories: [own, other],
                    currentUserId: 7,
                    onAddStory: () {},
                    onViewStory: (_, _) {},
                    style: style,
                  ),
          ),
        ),
      );
      await tester.pump();
    }

    StoryRing ring(WidgetTester tester, Object id) =>
        tester.widget<StoryRing>(find.byKey(ValueKey('story-segments-$id')));

    testWidgets('circle style keeps circular 64px avatars', (tester) async {
      await show(tester, null);
      expect(ring(tester, 7).cornerRadius, isNull);
      expect(ring(tester, 8).cornerRadius, isNull);
      expect(
        tester.getSize(find.byKey(const ValueKey('story-avatar-7'))),
        const Size(64, 64),
      );
      expect(find.byType(ClipOval), findsNWidgets(2));
      expect(find.byType(ClipRRect), findsNothing);
    });

    testWidgets(
      'rectangle draws 64x80 radius-16 cards, names, badge and the You menu',
      (tester) async {
        await show(tester, StoryStyle.rectangle);
        for (final id in [7, 8]) {
          expect(
            tester.getSize(find.byKey(ValueKey('story-avatar-$id'))),
            const Size(64, 80),
          );
          expect(ring(tester, id).cornerRadius, 16);
        }
        expect(find.byType(ClipOval), findsNothing);
        expect(find.byType(ClipRRect), findsNWidgets(2));
        expect(find.text('You'), findsOneWidget);
        expect(find.text('Traveler 8'), findsOneWidget);
        // Names sit under the cards.
        expect(
          tester.getTopLeft(find.text('Traveler 8')).dy,
          greaterThan(
            tester
                .getBottomLeft(find.byKey(const ValueKey('story-avatar-8')))
                .dy,
          ),
        );
        // Orange + badge overlaps the own card's bottom-right corner.
        final badge = tester.getCenter(
          find.byKey(const ValueKey('add-story-photo')),
        );
        final card = tester.getRect(
          find.byKey(const ValueKey('story-avatar-7')),
        );
        expect(badge.dx, closeTo(card.right - 16 * (1 - 1 / 1.4142135), .5));
        expect(badge.dy, closeTo(card.bottom - 16 * (1 - 1 / 1.4142135), .5));

        await tester.tap(find.byKey(const ValueKey('your-story-bubble')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('view-my-story')), findsOneWidget);
        expect(find.byKey(const ValueKey('add-new-story')), findsOneWidget);
      },
    );

    testWidgets('rectangle row is taller than the circle row', (tester) async {
      await show(tester, StoryStyle.rectangle);
      final context = tester.element(find.byType(HomeStories));
      expect(
        HomeStories.preferredHeight(context, StoryStyle.rectangle),
        greaterThan(HomeStories.preferredHeight(context)),
      );
      expect(
        tester.getSize(find.byType(HomeStories)).height,
        HomeStories.preferredHeight(context, StoryStyle.rectangle),
      );
    });

    testWidgets('loading skeleton follows the style', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HomeStories(
              stories: [],
              loading: true,
              style: StoryStyle.rectangle,
            ),
          ),
        ),
      );
      expect(
        tester.getSize(
          find.byKey(const ValueKey('story-skeleton-avatar')).first,
        ),
        const Size(64, 80),
      );
    });
  });

  group('story style preference', () {
    test(
      'defaults to rectangle, persists, survives logout, resets on clear',
      () async {
        expect(preferences.storyStyle.value, StoryStyle.rectangle);
        await preferences.saveStoryStyle(StoryStyle.circle);
        expect(
          preferences.getString(PreferencesManager.storyStyleKey),
          'circle',
        );
        await preferences.init();
        expect(preferences.storyStyle.value, StoryStyle.circle);
        await preferences.clearSession();
        await preferences.init();
        expect(preferences.storyStyle.value, StoryStyle.circle);
        await preferences.clear();
        expect(preferences.storyStyle.value, StoryStyle.rectangle);
      },
    );

    test('unchosen or unknown stored values fall back to rectangle', () {
      expect(StoryStyle.parse('hexagon'), StoryStyle.rectangle);
      expect(StoryStyle.parse(null), StoryStyle.rectangle);
      expect(StoryStyle.parse('circle'), StoryStyle.circle);
    });
  });

  group('Settings Story Style row', () {
    Future<void> show(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final user = settings.settingsCubit(settings.SettingsApi());
      addTearDown(user.close);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            theme: darkTheme,
            home: SettingsScreen(currentUser: user),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final row = find.byKey(const ValueKey('settings-story-style'));
    Finder rowValue(String value) =>
        find.descendant(of: row, matching: find.text(value));

    testWidgets('shows the current value (Rectangle by default) beside a '
        'chevron, and no debug chips remain', (tester) async {
      await show(tester);
      expect(
        find.descendant(of: row, matching: find.text('Story Style')),
        findsOneWidget,
      );
      expect(rowValue('Rectangle'), findsOneWidget);
      expect(
        find.descendant(
          of: row,
          matching: find.byIcon(Icons.chevron_right_rounded),
        ),
        findsOneWidget,
      );
      expect(find.byType(ChoiceChip), findsNothing);
      // Sits in App Preferences right after Language.
      expect(
        tester.getTopLeft(row).dy,
        greaterThan(tester.getTopLeft(find.text('Language')).dy),
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('sheet shows both shapes with previews; picking one closes '
        'it, saves it and updates the row', (tester) async {
      await show(tester);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.byType(StoryStyleBottomSheet), findsOneWidget);
      final sheet = find.byType(StoryStyleBottomSheet);
      expect(
        find.descendant(of: sheet, matching: find.text('Story Style')),
        findsOneWidget,
      );
      for (final style in StoryStyle.values) {
        expect(
          find.byKey(ValueKey('story-style-preview-${style.name}')),
          findsOneWidget,
        );
      }
      expect(
        tester.getSize(
          find.byKey(const ValueKey('story-style-preview-rectangle')),
        ),
        const Size(24, 30),
      );
      expect(
        tester.getSize(
          find.byKey(const ValueKey('story-style-preview-circle')),
        ),
        const Size(24, 24),
      );
      // Rectangle is listed first and checked.
      expect(
        tester.getTopLeft(find.text('Rectangle').last).dy,
        lessThan(tester.getTopLeft(find.text('Circle')).dy),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('story-style-option-rectangle')),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('story-style-option-circle')));
      await tester.pumpAndSettle();
      expect(find.byType(StoryStyleBottomSheet), findsNothing);
      expect(preferences.storyStyle.value, StoryStyle.circle);
      expect(preferences.getString(PreferencesManager.storyStyleKey), 'circle');
      expect(rowValue('Circle'), findsOneWidget);

      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('story-style-option-circle')),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('story-style-option-rectangle')),
      );
      await tester.pumpAndSettle();
      expect(rowValue('Rectangle'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('dismissing the sheet keeps the current style', (tester) async {
      await show(tester);
      await tester.tap(row);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();
      expect(find.byType(StoryStyleBottomSheet), findsNothing);
      expect(preferences.storyStyle.value, StoryStyle.rectangle);
      expect(preferences.getString(PreferencesManager.storyStyleKey), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('Home updates immediately when the preference changes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: preferences.storyStyle,
            builder: (_, style, _) => HomeStories(
              stories: [StoryGroup.fromJson(groupJson(8))],
              style: style,
            ),
          ),
        ),
      ),
    );
    StoryRing ring() => tester.widget<StoryRing>(
      find.byKey(const ValueKey('story-segments-8')),
    );
    expect(ring().cornerRadius, 16);
    await preferences.saveStoryStyle(StoryStyle.circle);
    await tester.pump();
    expect(ring().cornerRadius, isNull);
  });
}
