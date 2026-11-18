import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/stories/cubit/story_viewer_cubit.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';
import 'package:travibe/features/stories/data/story_elements.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/screens/story_viewer_screen.dart';
import 'package:travibe/features/stories/widgets/story_viewer_canvas.dart';

import 'fixtures.dart';
import 'story_viewer_test.dart' show ViewerRepo, viewerDetail, viewerGroup;

void main() {
  setUp(() async {
    ScreenUtil.configure(
      data: const MediaQueryData(size: Size(390, 844)),
      designSize: const Size(390, 844),
      minTextAdapt: false,
      splitScreenMode: false,
    );
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('viewer-mention-test');
  });
  tearDown(() => PreferencesManager().clear());

  const bubble = StoryTextLayer(
    id: 't',
    text: 'Best coffee with my best friend @sarakhaled12',
    center: Offset(.5, .4),
  );

  Future<List<int>> open(
    WidgetTester tester,
    ViewerRepo repo, {
    required bool resolved,
    List<StoryEditorLayer> layers = const [bubble],
    List<StoryMentionedUser> hidden = const [],
    List<int>? profileLoads,
  }) async {
    repo.handler = (id) async {
      final json = viewerDetail(
        id,
        elements: [
          ...StoryElements.encode(layers),
          if (hidden.isNotEmpty) legacyMentionsElement(hidden),
        ],
      );
      json['mentions'] = [
        if (resolved)
          {
            'handle': 'sarakhaled12',
            'user': {'id': 5, 'username': 'sarakhaled12'},
          },
      ];
      return StoryDetail.fromJson(json);
    };
    final opened = <int>[];
    final photo = MemoryImage(photoBytes());
    await tester.pumpWidget(
      MaterialApp(
        home: StoryViewerScreen(
          groups: [
            viewerGroup(7, [1, 2]),
          ],
          initialAuthorId: 7,
          repo: repo,
          imageProvider: (_) => photo,
          onOpenProfile: (context, userId) async => opened.add(userId),
          loadMentionProfile: (userId) async {
            profileLoads?.add(userId);
            return (name: 'Sara Khaled', avatarUrl: null);
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return opened;
  }

  Rect canvasRect(WidgetTester tester) =>
      tester.getRect(find.byType(StoryViewerCanvas));

  /// The `@username` in the bubble, canvas-local.
  StoryMentionHit hitOf(WidgetTester tester) {
    final rect = canvasRect(tester);
    final layers = tester
        .widget<StoryViewerCanvas>(find.byType(StoryViewerCanvas))
        .layers;
    return StoryViewerCanvas.mentionHitAt(
      layers,
      _scan(layers, rect.size)!,
      rect.size,
    )!;
  }

  Offset mentionCenter(WidgetTester tester) =>
      canvasRect(tester).topLeft + hitOf(tester).rect.center;

  bool paused(WidgetTester tester) => tester
      .widget<BlocConsumer<StoryViewerCubit, StoryViewerState>>(
        find.byWidgetPredicate(
          (w) => w is BlocConsumer<StoryViewerCubit, StoryViewerState>,
        ),
      )
      .bloc!
      .state
      .paused;

  final popover = find.byKey(const ValueKey('story-mention-popover'));

  testWidgets('text bubble: white text with the @username in orange', (
    tester,
  ) async {
    await open(tester, ViewerRepo(), resolved: true);
    expect(find.byKey(const ValueKey('story-text-bubble')), findsOneWidget);
    final text = tester.widget<RichText>(
      find.descendant(
        of: find.byKey(const ValueKey('story-text-bubble')),
        matching: find.byType(RichText),
      ),
    );
    final span = text.text as TextSpan;
    expect(span.style!.color, Colors.white);
    final handle = span.children!.cast<TextSpan>().last;
    expect(handle.text, '@sarakhaled12');
    expect(handle.style!.color, DarkColors.primaryColor);
  });

  testWidgets(
    'tapping the @username pauses and shows the card under the bubble',
    (tester) async {
      final repo = ViewerRepo();
      final loads = <int>[];
      final opened = await open(
        tester,
        repo,
        resolved: true,
        profileLoads: loads,
      );
      expect(paused(tester), isFalse);
      final hit = hitOf(tester);
      await tester.tapAt(mentionCenter(tester));
      await tester.pump();
      expect(popover, findsOneWidget);
      expect(find.text('View profile'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(find.text('Sara Khaled'), findsOneWidget);
      expect(loads, [5]);
      expect(paused(tester), isTrue);
      // Under the whole bubble (not just the handle), with a pointer.
      final card = tester.getRect(popover);
      final bubbleOnScreen = hit.bubble.shift(canvasRect(tester).topLeft);
      expect(card.top, greaterThanOrEqualTo(bubbleOnScreen.bottom));
      expect(card.top - bubbleOnScreen.bottom, lessThan(12));
      expect(
        find.descendant(of: popover, matching: find.byType(CustomPaint)),
        findsWidgets,
      );
      // The card doesn't open the profile by itself, and doesn't advance.
      expect(opened, isEmpty);
      expect(repo.calls, [1]);

      await tester.tap(
        find.byKey(const ValueKey('story-mention-view-profile')),
      );
      await tester.pump();
      expect(opened, [5]);
      expect(popover, findsNothing);
      expect(repo.calls, [1]);
      expect(paused(tester), isFalse);
    },
  );

  testWidgets('tapping elsewhere closes the card and resumes, not next', (
    tester,
  ) async {
    final repo = ViewerRepo();
    final opened = await open(tester, repo, resolved: true);
    await tester.tapAt(mentionCenter(tester));
    await tester.pump();
    expect(paused(tester), isTrue);
    await tester.tapAt(const Offset(20, 300));
    await tester.pump();
    expect(popover, findsNothing);
    expect(paused(tester), isFalse);
    expect(opened, isEmpty);
    // The dismissing tap is not also a "previous/next" tap.
    expect(repo.calls, [1]);
  });

  testWidgets('plain words in the bubble are ordinary taps', (tester) async {
    await open(tester, ViewerRepo(), resolved: true);
    final rect = canvasRect(tester);
    final hit = hitOf(tester);
    // Near the bubble's top-left is "Best", not the handle.
    final plain = hit.bubble.topLeft + const Offset(30, 18);
    expect(
      StoryViewerCanvas.mentionHitAt(const [bubble], plain, rect.size),
      isNull,
    );
    await tester.tapAt(rect.topLeft + plain);
    await tester.pump();
    await tester.pump();
    expect(popover, findsNothing);
  });

  testWidgets('an unresolved (blocked/unknown) mention is a normal tap', (
    tester,
  ) async {
    final repo = ViewerRepo();
    final opened = await open(tester, repo, resolved: false);
    await tester.tapAt(mentionCenter(tester));
    await tester.pump();
    await tester.pump();
    expect(opened, isEmpty);
    expect(popover, findsNothing);
    // Previous/next navigation ran (the story was requested again).
    expect(repo.calls, hasLength(2));
  });

  testWidgets('old hidden-mentions element ("\\u200B") draws nothing', (
    tester,
  ) async {
    await open(
      tester,
      ViewerRepo(),
      resolved: true,
      layers: const [],
      hidden: const [StoryMentionedUser(id: 5, username: 'sarakhaled12')],
    );
    expect(
      tester.widget<StoryViewerCanvas>(find.byType(StoryViewerCanvas)).layers,
      isEmpty,
    );
    expect(find.textContaining('sarakhaled12'), findsNothing);
    expect(find.byKey(const ValueKey('story-text-bubble')), findsNothing);
  });

  testWidgets('hit testing returns the handle and the whole bubble', (
    tester,
  ) async {
    const size = Size(390, 800);
    const text = StoryTextLayer(id: 't', text: 'Hi @sara and you');
    final point = _scan(const [text], size)!;
    final hit = StoryViewerCanvas.mentionHitAt(const [text], point, size)!;
    expect(hit.username, 'sara');
    expect(hit.rect.contains(point), isTrue);
    expect(hit.bubble.contains(hit.rect.center), isTrue);
    expect(hit.bubble.width, greaterThan(hit.rect.width));
    expect(
      StoryViewerCanvas.mentionHitAt(
        const [StoryTextLayer(id: 'p', text: 'no mention here')],
        const Offset(195, 400),
        size,
      ),
      isNull,
    );
  });
}

/// First point (scanning a grid; text may wrap) that hits a mention.
Offset? _scan(List<StoryEditorLayer> layers, Size size) {
  for (var y = 0.0; y < size.height; y += 4) {
    for (var x = 0.0; x < size.width; x += 4) {
      if (StoryViewerCanvas.mentionHitAt(layers, Offset(x, y), size) != null) {
        return Offset(x, y);
      }
    }
  }
  return null;
}
