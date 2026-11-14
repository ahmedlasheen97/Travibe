import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/home/widgets/home_stories.dart';
import 'package:travibe/features/stories/screens/story_editor_screen.dart';
import 'package:travibe/features/stories/widgets/post_story_sheet.dart';
import 'package:travibe/features/stories/widgets/story_entry.dart';

import 'fixtures.dart';

void main() {
  setUp(() {
    ScreenUtil.configure(
      data: const MediaQueryData(size: Size(390, 844)),
      designSize: const Size(390, 844),
      minTextAdapt: false,
      splitScreenMode: false,
    );
  });

  TestWidgetsFlutterBinding.ensureInitialized();
  late StubStoryPhotoRepo repo;
  setUp(() => repo = StubStoryPhotoRepo());

  test(
    'registered camera and gallery SVGs decode at their native dimensions',
    () async {
      for (final asset in ['camera', 'gallery']) {
        final picture = await vg.loadPicture(
          SvgAssetLoader('assets/images/interactions/$asset.svg'),
          null,
        );
        expect(picture.size, const Size(24, 24));
        picture.picture.dispose();
      }
    },
  );

  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: StoryEntry(
            repo: repo,
            builder: (_, addStory) =>
                HomeStories(stories: const [], onAddStory: addStory),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('add-story-photo')));
    await tester.pumpAndSettle();
    expect(find.byType(PostStorySheet), findsOneWidget);
  }

  testWidgets('first avatar plus opens one current Story sheet', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('add-story-photo')));
    await tester.tap(
      find.byKey(const ValueKey('add-story-photo')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.byType(PostStorySheet), findsOneWidget);
    expect(find.text('Post a Story'), findsOneWidget);
    expect(find.text('Take a Photo'), findsOneWidget);
    expect(find.text('Choose from Gallery'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Take a Photo'),
          )
          .onPressed,
      isNotNull,
    );
    final assets = tester
        .widgetList<SvgPicture>(find.byType(SvgPicture))
        .map((svg) => (svg.bytesLoader as SvgAssetLoader).assetName);
    expect(
      assets,
      containsAll([
        'assets/images/interactions/camera.svg',
        'assets/images/interactions/gallery.svg',
      ]),
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('story-camera')))
          .style!
          .backgroundColor!
          .resolve({}),
      DarkColors.primaryColor,
    );
    expect(repo.picks, 0);
  });

  testWidgets('gallery cancellation stays on sheet and does not open editor', (
    tester,
  ) async {
    await show(tester);
    await openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('story-gallery')));
    await tester.pumpAndSettle();
    expect(repo.picks, 1);
    expect(find.byType(PostStorySheet), findsOneWidget);
    expect(find.byType(StoryEditorScreen), findsNothing);
  });

  testWidgets('camera cancellation stays on sheet and allows another capture', (
    tester,
  ) async {
    await show(tester);
    await openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('story-camera')));
    await tester.pumpAndSettle();
    expect(repo.captures, 1);
    expect(repo.picks, 0);
    expect(find.byType(PostStorySheet), findsOneWidget);
    expect(find.byType(StoryEditorScreen), findsNothing);
    await tester.tap(find.byKey(const ValueKey('story-camera')));
    await tester.pumpAndSettle();
    expect(repo.captures, 2);
  });

  testWidgets(
    'camera capture opens the same editor directly without network or publication',
    (tester) async {
      var networkAttempts = 0;
      await HttpOverrides.runZoned(
        () async {
          final captured = draft();
          repo.selected = captured;
          await show(tester);
          await openSheet(tester);
          await tester.tap(find.byKey(const ValueKey('story-camera')));
          await tester.pumpAndSettle();
          expect(repo.captures, 1);
          expect(repo.picks, 0);
          expect(find.byType(PostStorySheet), findsNothing);
          expect(
            tester
                .widget<StoryEditorScreen>(find.byType(StoryEditorScreen))
                .draft,
            same(captured),
          );
          final post = tester.widget<FilledButton>(
            find.byKey(const ValueKey('story-post')),
          );
          expect(post.onPressed, isNull);
          expect(
            post.style!.backgroundColor!.resolve({WidgetState.disabled}),
            DarkColors.primaryColor,
          );
          await tester.tap(find.byKey(const ValueKey('story-post')));
          await tester.pump();
          expect(find.byType(StoryEditorScreen), findsOneWidget);
          expect(captured.layers, isEmpty);
          expect(tester.takeException(), isNull);
        },
        createHttpClient: (_) {
          networkAttempts++;
          throw StateError('No Story HTTP calls permitted');
        },
      );
      expect(networkAttempts, 0);
    },
  );

  testWidgets('camera permission error stays local and gallery still works', (
    tester,
  ) async {
    repo.failure = PlatformException(
      code: 'camera_access_denied',
      message: 'private device details',
    );
    await show(tester);
    await openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('story-camera')));
    await tester.pumpAndSettle();
    expect(
      find.text('Camera access is restricted. Check your device settings.'),
      findsOneWidget,
    );
    expect(find.byType(StoryEditorScreen), findsNothing);
    repo.failure = null;
    repo.selected = draft();
    await tester.tap(find.byKey(const ValueKey('story-gallery')));
    await tester.pumpAndSettle();
    expect(repo.picks, 1);
    expect(find.byType(StoryEditorScreen), findsOneWidget);
  });

  testWidgets(
    'camera and gallery share one busy lock; dismissed results do not navigate',
    (tester) async {
      repo.selection = Completer();
      await show(tester);
      await openSheet(tester);
      await tester.tap(find.byKey(const ValueKey('story-camera')));
      await tester.tap(find.byKey(const ValueKey('story-camera')));
      await tester.tap(find.byKey(const ValueKey('story-gallery')));
      await tester.pump();
      expect(repo.captures, 1);
      expect(repo.picks, 0);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('story-camera')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('story-gallery')))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      repo.selection!.complete(draft());
      await tester.pumpAndSettle();
      expect(find.byType(StoryEditorScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('picker errors stay local and can be retried', (tester) async {
    repo.failure = PlatformException(code: 'unavailable');
    await show(tester);
    await openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('story-gallery')));
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to open that photo. Please try again.'),
      findsOneWidget,
    );
    repo.failure = null;
    await tester.tap(find.byKey(const ValueKey('story-gallery')));
    await tester.pumpAndSettle();
    expect(repo.picks, 2);
    expect(find.byType(StoryEditorScreen), findsNothing);
  });

  testWidgets('duplicate gallery taps invoke one picker', (tester) async {
    repo.selection = Completer();
    await show(tester);
    await openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('story-gallery')));
    await tester.tap(find.byKey(const ValueKey('story-gallery')));
    await tester.pump();
    expect(repo.picks, 1);
    repo.selection!.complete(null);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'selection opens local editor; no placeholder tools and publication stays disabled without network',
    (tester) async {
      var networkAttempts = 0;
      await HttpOverrides.runZoned(
        () async {
          final selected = draft();
          repo.selected = selected;
          await show(tester);
          await openSheet(tester);
          await tester.tap(find.byKey(const ValueKey('story-gallery')));
          await tester.pumpAndSettle();
          final editor = tester.widget<StoryEditorScreen>(
            find.byType(StoryEditorScreen),
          );
          expect(editor.draft, same(selected));
          final image = tester.widget<Image>(
            find.byKey(const ValueKey('story-background')),
          );
          expect(image.fit, BoxFit.cover);
          expect((image.image as MemoryImage).bytes, photoBytes());
          expect(
            tester
                .widget<FilledButton>(find.byKey(const ValueKey('story-post')))
                .onPressed,
            isNull,
          );
          // Mention, emoji and draw are live tools; Location was removed.
          expect(
            tester
                .widgetList<IconButton>(find.byType(IconButton))
                .where(
                  (button) => button.tooltip?.contains('coming soon') ?? false,
                ),
            isEmpty,
          );
          for (final key in [
            'story-mention-tool',
            'story-emoji-tool',
            'story-draw-tool',
          ]) {
            expect(find.byKey(ValueKey(key)), findsOneWidget);
          }
          await tester.tap(find.byKey(const ValueKey('story-post')));
          await tester.pump();
          expect(find.byType(StoryEditorScreen), findsOneWidget);
          expect(selected.layers, isEmpty);
          await tester.tap(find.byKey(const ValueKey('story-back')));
          await tester.pumpAndSettle();
          expect(find.byType(StoryEditorScreen), findsNothing);
          expect(find.byType(HomeStories), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
        createHttpClient: (_) {
          networkAttempts++;
          throw StateError('No network permitted');
        },
      );
      expect(networkAttempts, 0);
    },
  );

  testWidgets(
    'Android startup recovery navigates once without opening picker',
    (tester) async {
      repo.recovered = draft();
      await show(tester);
      expect(repo.recoveries, 1);
      expect(repo.picks, 0);
      expect(find.byType(StoryEditorScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('story-back')));
      await tester.pumpAndSettle();
      expect(repo.recoveries, 1);
      expect(find.byType(StoryEditorScreen), findsNothing);
    },
  );

  testWidgets('disposed entry does not navigate after picker completion', (
    tester,
  ) async {
    repo.selection = Completer();
    await show(tester);
    await openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('story-gallery')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    repo.selection!.complete(draft());
    await tester.pumpAndSettle();
    expect(find.byType(StoryEditorScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
