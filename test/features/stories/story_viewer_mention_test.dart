import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/stories/cubit/story_viewer_cubit.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
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

  const mention = StoryMentionLayer(
    id: 'm',
    userId: 5,
    username: 'Sara',
    style: StoryMentionStyle.brand,
    center: Offset(.75, .4),
    scale: 1.5,
    rotation: .3,
  );

  Future<List<int>> open(
    WidgetTester tester,
    ViewerRepo repo, {
    required bool resolved,
    List<StoryEditorLayer> layers = const [mention],
    List<int>? profileLoads,
  }) async {
    repo.handler = (id) async {
      final json = viewerDetail(id, elements: StoryElements.encode(layers));
      json['mentions'] = [
        if (resolved)
          {
            'handle': 'sara',
            'user': {'id': 5, 'username': 'sara'},
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

  Offset mentionCenter(WidgetTester tester) {
    final rect = tester.getRect(find.byType(StoryViewerCanvas));
    final layer = find.byKey(const ValueKey('story-viewer-layer-m'));
    expect(layer, findsOneWidget);
    expect(find.text('@Sara'), findsOneWidget);
    return rect.topLeft +
        Offset(rect.width * mention.center.dx, rect.height * mention.center.dy);
  }

  bool paused(WidgetTester tester) => tester
      .widget<BlocConsumer<StoryViewerCubit, StoryViewerState>>(
        find.byWidgetPredicate(
          (w) => w is BlocConsumer<StoryViewerCubit, StoryViewerState>,
        ),
      )
      .bloc!
      .state
      .paused;

  testWidgets(
    'tapping a resolved mention pauses and shows the View profile card',
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
      // Same glass bubble and orange @username as in the editor.
      expect(
        find.byKey(const ValueKey('story-mention-sticker')),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(find.text('@Sara')).style!.color,
        DarkColors.primaryColor,
      );
      await tester.tapAt(mentionCenter(tester));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('story-mention-popover')),
        findsOneWidget,
      );
      expect(find.text('View profile'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(find.text('Sara Khaled'), findsOneWidget);
      expect(loads, [5]);
      expect(paused(tester), isTrue);
      // The card doesn't open the profile by itself, and doesn't advance.
      expect(opened, isEmpty);
      expect(repo.calls, [1]);

      await tester.tap(
        find.byKey(const ValueKey('story-mention-view-profile')),
      );
      await tester.pump();
      expect(opened, [5]);
      expect(find.byKey(const ValueKey('story-mention-popover')), findsNothing);
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
    expect(find.byKey(const ValueKey('story-mention-popover')), findsNothing);
    expect(paused(tester), isFalse);
    expect(opened, isEmpty);
    // The dismissing tap is not also a "previous/next" tap.
    expect(repo.calls, [1]);
  });

  testWidgets('an @handle inside a text element opens the card too', (
    tester,
  ) async {
    const text = StoryTextLayer(
      id: 't',
      text: 'Best coffee with @sara',
      center: Offset(.5, .5),
    );
    final repo = ViewerRepo();
    final opened = await open(
      tester,
      repo,
      resolved: true,
      layers: const [text],
    );
    final rect = tester.getRect(find.byType(StoryViewerCanvas));
    final state = tester
        .widget<StoryViewerCanvas>(find.byType(StoryViewerCanvas))
        .layers;
    final hit = StoryViewerCanvas.mentionHitAt(
      state,
      // Somewhere on the handle.
      _scan(state, rect.size)!,
      rect.size,
    )!;
    expect(hit.username, 'sara');
    await tester.tapAt(rect.topLeft + hit.rect.center);
    await tester.pump();
    expect(find.byKey(const ValueKey('story-mention-popover')), findsOneWidget);
    // Plain words in the same element are ordinary taps.
    expect(opened, isEmpty);
  });

  testWidgets('a long username sticker shows in full and opens the card', (
    tester,
  ) async {
    const long = StoryMentionLayer(
      id: 'm',
      userId: 5,
      username: 'sara_khaled_the_traveler_from_cairo_2026',
      center: Offset(.5, .4),
    );
    final repo = ViewerRepo();
    repo.handler = (id) async {
      final json = viewerDetail(id, elements: StoryElements.encode([long]));
      json['mentions'] = [
        {
          'handle': long.username,
          'user': {'id': 5, 'username': long.username},
        },
      ];
      return StoryDetail.fromJson(json);
    };
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
          onOpenProfile: (context, userId) async {},
          loadMentionProfile: (userId) async => null,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final label = find.text('@${long.username}');
    expect(label, findsOneWidget);
    expect(tester.widget<Text>(label).maxLines, isNull);
    // Wrapped onto more than one line rather than cut off.
    expect(tester.getSize(label).height, greaterThan(40));
    await tester.tapAt(tester.getCenter(label));
    await tester.pump();
    expect(find.byKey(const ValueKey('story-mention-popover')), findsOneWidget);
    // No profile name yet: the card falls back to the @username.
    expect(find.text('View profile'), findsOneWidget);
  });

  testWidgets('an unresolved (blocked/unknown) mention falls through to next', (
    tester,
  ) async {
    final repo = ViewerRepo();
    final opened = await open(tester, repo, resolved: false);
    await tester.tapAt(mentionCenter(tester));
    await tester.pump();
    await tester.pump();
    expect(opened, isEmpty);
    expect(repo.calls, [1, 2]);
  });

  testWidgets('text mentions are highlighted and hit-tested by span', (
    tester,
  ) async {
    const size = Size(390, 800);
    const text = StoryTextLayer(id: 't', text: 'Hi @sara and you');
    final point = _scan(const [text], size)!;
    final hit = StoryViewerCanvas.mentionHitAt(const [text], point, size)!;
    expect(hit.username, 'sara');
    expect(hit.rect.contains(point), isTrue);
    // The middle of the element ("and") is not the mention.
    expect(
      StoryViewerCanvas.mentionHitAt(
        const [StoryTextLayer(id: 'p', text: 'no mention here')],
        const Offset(195, 400),
        size,
      ),
      isNull,
    );
  });

  test('mention hit testing honors scale and rotation', () {
    const size = Size(390, 800);
    final center = Offset(390 * .75, 800 * .4);
    expect(
      StoryViewerCanvas.mentionAt(const [mention], center, size),
      same(mention),
    );
    expect(
      StoryViewerCanvas.mentionAt(const [mention], const Offset(10, 10), size),
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
