import 'package:travibe/features/stories/screens/story_editor_screen.dart';
import 'package:travibe/features/stories/screens/story_viewer_screen.dart';
import 'story_viewer_test.dart' show ViewerRepo, viewerGroup;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/home/widgets/home_stories.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/widgets/post_story_sheet.dart';
import 'package:travibe/features/stories/widgets/story_entry.dart';
import 'package:travibe/features/stories/widgets/your_story_button.dart';

import 'fixtures.dart';
import 'story_publishing_test.dart' show groupJson;

StoryGroup ownGroup({int userId = 7, DateTime? expiry, String? name}) {
  final json = groupJson(userId);
  if (name != null) (json['user'] as Map)['name'] = name;
  ((json['stories'] as List).single as Map)['expires_at'] = expiry
      ?.toIso8601String();
  return StoryGroup.fromJson(json);
}

void main() {
  setUp(() {
    ScreenUtil.configure(
      data: const MediaQueryData(size: Size(390, 844)),
      designSize: const Size(390, 844),
      minTextAdapt: false,
      splitScreenMode: false,
    );
  });

  final session = PreferencesManager();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await session.init();
    await session.saveToken('test-popup-session');
  });
  tearDown(() async {
    await session.clear();
  });

  Future<void> show(
    WidgetTester tester, {
    List<StoryGroup> groups = const [],
    int? userId = 7,
    bool loading = false,
    bool creationFlow = false,
    VoidCallback? add,
    VoidCallback? onNavigation,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: GestureDetector(
            key: const ValueKey('test-bottom-navigation'),
            onTap: onNavigation,
            child: const SizedBox(
              height: 64,
              child: ColoredBox(color: Colors.orange),
            ),
          ),
          body: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 40),
              child: creationFlow
                  ? StoryEntry(
                      repo: StubStoryPhotoRepo()..selected = draft(),
                      builder: (_, onAdd) => HomeStories(
                        stories: groups,
                        currentUserId: userId,
                        onAddStory: onAdd,
                      ),
                    )
                  : HomeStories(
                      stories: groups,
                      currentUserId: userId,
                      loading: loading,
                      onAddStory: add,
                    ),
            ),
          ),
        ),
      ),
    );
    if (loading) {
      await tester.pump();
    } else {
      await tester.pumpAndSettle();
    }
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  Future<void> tapBubble(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('your-story-bubble')));
    await tester.pumpAndSettle();
  }

  final popup = find.byKey(const ValueKey('view-my-story'));

  testWidgets(
    'no active stories opens the existing camera/gallery sheet directly',
    (tester) async {
      await show(tester, creationFlow: true);
      await tapBubble(tester);
      expect(find.byType(PostStorySheet), findsOneWidget);
      expect(popup, findsNothing);
      expect(find.text('Take a Photo'), findsOneWidget);
    },
  );
  testWidgets(
    'active own story shows two actions and remains safe without a viewer callback',
    (tester) async {
      await show(
        tester,
        groups: [
          ownGroup(expiry: DateTime.now().add(const Duration(hours: 1))),
        ],
        creationFlow: true,
      );
      await tapBubble(tester);
      expect(find.byType(MenuItemButton), findsNWidgets(2));
      expect(find.text('View Story'), findsOneWidget);
      expect(find.text('Add to Story'), findsOneWidget);
      expect(tester.widget<MenuItemButton>(popup).onPressed, isNull);
      await tester.tap(find.text('View Story'));
      await tester.pumpAndSettle();
      expect(find.byType(PostStorySheet), findsNothing);
      expect(popup, findsOneWidget);
    },
  );
  testWidgets(
    'Add to Story dismisses popup and opens existing creation sheet',
    (tester) async {
      await show(
        tester,
        groups: [
          ownGroup(expiry: DateTime.now().add(const Duration(hours: 1))),
        ],
        creationFlow: true,
      );
      await tapBubble(tester);
      await tester.tap(find.byKey(const ValueKey('add-new-story')));
      await tester.pumpAndSettle();
      expect(popup, findsNothing);
      expect(find.byType(PostStorySheet), findsOneWidget);
    },
  );
  testWidgets(
    'orange plus badge opens the same own-story menu with active stories',
    (tester) async {
      var additions = 0;
      await show(
        tester,
        groups: [
          ownGroup(expiry: DateTime.now().add(const Duration(hours: 1))),
        ],
        add: () {
          additions++;
        },
      );
      final badge = find.descendant(
        of: find.byKey(const ValueKey('add-story-photo')),
        matching: find.byIcon(Icons.add),
      );
      await tester.tap(badge);
      await tester.pumpAndSettle();
      expect(additions, 0);
      expect(popup, findsOneWidget);
    },
  );
  testWidgets('outside tap dismisses without activating underlying content', (
    tester,
  ) async {
    var navigations = 0;
    await show(
      tester,
      onNavigation: () {
        navigations++;
      },
      groups: [ownGroup(expiry: DateTime.now().add(const Duration(hours: 1)))],
    );
    await tapBubble(tester);
    await tester.tap(find.byKey(const ValueKey('test-bottom-navigation')));
    await tester.pumpAndSettle();
    expect(popup, findsNothing);
    expect(navigations, 0);
    await tester.tap(find.byKey(const ValueKey('test-bottom-navigation')));
    await tester.pump();
    expect(navigations, 1);
  });
  testWidgets('removing own stories during refresh dismisses an open popup', (
    tester,
  ) async {
    var additions = 0;
    await show(
      tester,
      groups: [ownGroup(expiry: DateTime.now().add(const Duration(hours: 1)))],
    );
    await tapBubble(tester);
    await show(
      tester,
      add: () {
        additions++;
      },
    );
    expect(popup, findsNothing);
    await tapBubble(tester);
    expect(additions, 1);
  });
  testWidgets('repeated bubble taps toggle one popup without duplicates', (
    tester,
  ) async {
    await show(
      tester,
      groups: [ownGroup(expiry: DateTime.now().add(const Duration(hours: 1)))],
    );
    await tapBubble(tester);
    await tapBubble(tester);
    expect(popup, findsNothing);
    await tapBubble(tester);
    expect(popup, findsOneWidget);
    expect(find.byType(MenuItemButton), findsNWidgets(2));
  });
  testWidgets('expired and unknown-expiry records do not count as active', (
    tester,
  ) async {
    var additions = 0;
    for (final expiry in [
      DateTime.now().subtract(const Duration(seconds: 1)),
      null,
    ]) {
      await show(
        tester,
        groups: [ownGroup(expiry: expiry)],
        add: () {
          additions++;
        },
      );
      await tapBubble(tester);
      expect(popup, findsNothing);
    }
    expect(additions, 2);
  });
  testWidgets(
    'another author with the same displayed name is never treated as owner',
    (tester) async {
      var additions = 0;
      await show(
        tester,
        groups: [
          ownGroup(
            userId: 8,
            name: 'You',
            expiry: DateTime.now().add(const Duration(hours: 1)),
          ),
        ],
        add: () {
          additions++;
        },
      );
      await tapBubble(tester);
      expect(additions, 1);
      expect(popup, findsNothing);
    },
  );
  testWidgets('loading without own active data keeps Add Story usable', (
    tester,
  ) async {
    var additions = 0;
    await show(
      tester,
      loading: true,
      add: () {
        additions++;
      },
    );
    // Do not pumpAndSettle while a loading progress indicator is active.
    await tester.tap(find.byKey(const ValueKey('your-story-bubble')));
    await tester.pump();
    expect(additions, 1);
    expect(popup, findsNothing);
  });
  testWidgets(
    'account change dismisses popup and does not reuse old-session group',
    (tester) async {
      var additions = 0;
      await show(
        tester,
        groups: [
          ownGroup(expiry: DateTime.now().add(const Duration(hours: 1))),
        ],
        add: () {
          additions++;
        },
      );
      await tapBubble(tester);
      await session.saveToken('next-popup-session');
      await tester.pumpAndSettle();
      expect(popup, findsNothing);
      await tapBubble(tester);
      expect(popup, findsNothing);
      expect(additions, 1);
      await show(
        tester,
        userId: 8,
        groups: [
          ownGroup(
            userId: 8,
            expiry: DateTime.now().add(const Duration(hours: 1)),
          ),
        ],
      );
      await tapBubble(tester);
      expect(popup, findsOneWidget);
    },
  );
  testWidgets('last active expiry closes an open popup, next tap opens Add', (
    tester,
  ) async {
    var now = DateTime.utc(2030);
    var additions = 0;
    final group = ownGroup(expiry: now.add(const Duration(seconds: 1)));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: YourStoryButton(
            group: group,
            currentUserId: 7,
            now: () => now,
            onAddStory: () {
              additions++;
            },
            child: const SizedBox(width: 64, height: 88, child: Text('You')),
          ),
        ),
      ),
    );
    await tapBubble(tester);
    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(popup, findsNothing);
    await tapBubble(tester);
    expect(additions, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('popup uses original SVG assets at 24px without a ColorFilter', (
    tester,
  ) async {
    final yaml = File('pubspec.yaml').readAsStringSync();
    expect(yaml, contains('- assets/images/interactions/'));
    await show(
      tester,
      groups: [ownGroup(expiry: DateTime.now().add(const Duration(hours: 1)))],
    );
    await tapBubble(tester);
    for (final item in [popup, find.byKey(const ValueKey('add-new-story'))]) {
      final svg = tester.widget<SvgPicture>(
        find.descendant(of: item, matching: find.byType(SvgPicture)),
      );
      expect(svg.width, 24);
      expect(svg.height, 24);
      expect(svg.colorFilter, isNull);
      expect(
        (svg.bytesLoader as SvgAssetLoader).assetName,
        item == popup
            ? 'assets/images/interactions/story.svg'
            : 'assets/images/interactions/add.svg',
      );
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'root overlay popup stays inside safe screen bounds at a bottom/right anchor',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(
        top: 24,
        bottom: 20,
        right: 12,
      );
      tester.view.viewPadding = const FakeViewPadding(
        top: 24,
        bottom: 20,
        right: 12,
      );
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: YourStoryButton(
                group: ownGroup(
                  expiry: DateTime.now().add(const Duration(hours: 1)),
                ),
                currentUserId: 7,
                child: const SizedBox(
                  width: 64,
                  height: 88,
                  child: Text('You'),
                ),
              ),
            ),
          ),
        ),
      );
      await tapBubble(tester);
      final view = tester.getRect(popup);
      final add = tester.getRect(find.byKey(const ValueKey('add-new-story')));
      expect(view.left, greaterThanOrEqualTo(0));
      expect(add.right, lessThanOrEqualTo(308));
      expect(view.top, greaterThanOrEqualTo(24));
      expect(add.bottom, lessThanOrEqualTo(460));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final width in [320.0, 375.0, 390.0, 393.0, 430.0]) {
    testWidgets('20px plus overlaps the bottom-right avatar edge at $width', (
      tester,
    ) async {
      ScreenUtil.configure(
        data: MediaQueryData(size: Size(width, 844)),
        designSize: const Size(390, 844),
      );
      await show(tester);
      final badge = tester.getRect(
        find.byKey(const ValueKey('add-story-photo')),
      );
      final avatar = tester.getRect(
        find.byKey(const ValueKey('story-avatar-you')),
      );
      final ring = tester.getRect(find.byKey(const ValueKey('story-ring-you')));
      expect(badge.width, closeTo(20, .0001));
      expect(badge.height, closeTo(20, .0001));
      expect(ring.width, closeTo(ring.height, .0001));
      expect(avatar.width, closeTo(avatar.height, .0001));
      if (width == 390) {
        expect(avatar.size, const Size.square(64));
        expect(ring.size, const Size.square(72));
      }
      expect(
        (badge.center - avatar.center).distance,
        closeTo(avatar.width / 2, .0001),
      );
      expect(badge.center.dx, greaterThan(avatar.center.dx));
      expect(badge.center.dy, greaterThan(avatar.center.dy));
      expect(badge.right, lessThanOrEqualTo(ring.right));
      expect(badge.bottom, lessThanOrEqualTo(ring.bottom));
      expect(
        (badge.center - avatar.center).distance + badge.width / 2,
        greaterThan(avatar.width / 2),
      );
      expect(
        (badge.center - avatar.center).distance - badge.width / 2,
        lessThan(avatar.width / 2),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'own plus selects Add to Story then the existing gallery/editor flow once',
    (tester) async {
      await show(
        tester,
        groups: [
          ownGroup(expiry: DateTime.now().add(const Duration(hours: 1))),
        ],
        creationFlow: true,
      );
      await tester.tap(find.byKey(const ValueKey('add-story-photo')));
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNWidgets(2));
      expect(find.byType(PostStorySheet), findsNothing);
      await tester.tap(find.text('Add to Story'));
      await tester.pumpAndSettle();
      expect(popup, findsNothing);
      expect(find.byType(PostStorySheet), findsOneWidget);
      await tester.tap(find.text('Choose from Gallery'));
      await tester.pumpAndSettle();
      expect(find.byType(StoryEditorScreen), findsOneWidget);
      expect(find.byType(PostStorySheet), findsNothing);
    },
  );

  testWidgets(
    'own plus View Story opens existing viewer with the original story order',
    (tester) async {
      final groups = [
        viewerGroup(7, [2, 1]),
        viewerGroup(8, [3]),
      ];
      final repo = ViewerRepo();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => HomeStories(
                stories: groups,
                currentUserId: 7,
                onViewStory: (loaded, author) => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => StoryViewerScreen(
                      groups: loaded,
                      initialAuthorId: author,
                      currentUserId: 7,
                      repo: repo,
                      imageProvider: (_) => MemoryImage(photoBytes()),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('add-story-photo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View Story'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(StoryViewerScreen), findsOneWidget);
      final viewer = tester.widget<StoryViewerScreen>(
        find.byType(StoryViewerScreen),
      );
      expect(viewer.initialAuthorId, 7);
      expect(viewer.groups.first.stories.map((story) => story.id), [2, 1]);
      expect(repo.calls.first, 2);
      expect(find.byKey(const ValueKey('view-my-story')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('expired own story plus opens creation directly', (tester) async {
    await show(
      tester,
      groups: [
        ownGroup(expiry: DateTime.now().subtract(const Duration(seconds: 1))),
      ],
      creationFlow: true,
    );
    await tester.tap(find.byKey(const ValueKey('add-story-photo')));
    await tester.pumpAndSettle();
    expect(find.byType(PostStorySheet), findsOneWidget);
    expect(popup, findsNothing);
  });
}
