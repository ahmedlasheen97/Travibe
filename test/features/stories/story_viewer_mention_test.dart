import 'package:flutter/material.dart';
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
  }) async {
    repo.handler = (id) async {
      final json = viewerDetail(id, elements: StoryElements.encode([mention]));
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

  testWidgets('tapping a resolved mention opens that profile, not next', (
    tester,
  ) async {
    final repo = ViewerRepo();
    final opened = await open(tester, repo, resolved: true);
    await tester.tapAt(mentionCenter(tester));
    await tester.pump();
    expect(opened, [5]);
    expect(repo.calls, [1]);
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
