import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/constants/feature_flags.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/screens/story_editor_screen.dart';
import 'package:travibe/features/stories/screens/story_viewer_screen.dart';

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
    await PreferencesManager().saveToken('reshare-test');
  });
  tearDown(() => PreferencesManager().clear());

  test('reshare UI is off until the backend ships', () {
    expect(kEnableStoryReshare, isFalse);
  });

  test('proposed fields parse; absent or malformed ones are safe', () {
    final plain = StoryDetail.fromJson(viewerDetail(1));
    expect(plain.allowReshare, isTrue);
    expect(plain.canReshare, isFalse);
    expect(plain.resharedFrom, isNull);
    final json = viewerDetail(2)
      ..['allow_reshare'] = false
      ..['can_reshare'] = true
      ..['reshared_from'] = {
        'story_id': 40,
        'user': {'id': 9, 'name': 'Sara Adel', 'avatar_url': null},
      };
    final reshared = StoryDetail.fromJson(json);
    expect(reshared.allowReshare, isFalse);
    expect(reshared.canReshare, isTrue);
    expect(reshared.resharedFrom!.id, 40);
    expect(reshared.resharedFrom!.user.name, 'Sara Adel');
    expect(
      StoryDetail.fromJson(
        viewerDetail(3)..['reshared_from'] = {'story_id': 'x'},
      ).resharedFrom,
      isNull,
    );
  });

  Future<({List<int> reshared, List<int> opened})> open(
    WidgetTester tester, {
    bool enable = true,
    bool canReshare = true,
    Map<String, dynamic>? resharedFrom,
    bool injectReshare = true,
  }) async {
    final repo = ViewerRepo()
      ..handler = (id) async {
        final json = viewerDetail(id)
          ..['is_mine'] = false
          ..['can_reshare'] = canReshare
          ..['created_at'] = DateTime.now()
              .subtract(const Duration(hours: 12))
              .toIso8601String();
        if (resharedFrom != null) json['reshared_from'] = resharedFrom;
        return StoryDetail.fromJson(json);
      };
    final reshared = <int>[], opened = <int>[];
    final photo = MemoryImage(photoBytes());
    await tester.pumpWidget(
      MaterialApp(
        home: StoryViewerScreen(
          groups: [
            viewerGroup(7, [1]),
          ],
          initialAuthorId: 7,
          currentUserId: 99,
          repo: repo,
          imageProvider: (_) => photo,
          enableReshare: enable,
          onOpenProfile: (context, userId) async => opened.add(userId),
          onReshare: injectReshare
              ? (context, story) async => reshared.add(story.id)
              : null,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return (reshared: reshared, opened: opened);
  }

  final reshareButton = find.byKey(const ValueKey('story-reshare'));

  testWidgets('Reshare shows above the reply bar when allowed', (tester) async {
    final calls = await open(tester);
    expect(reshareButton, findsOneWidget);
    expect(find.text('Reshare'), findsOneWidget);
    expect(
      tester.getBottomLeft(reshareButton).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey('story-other-controls')))
            .dy,
      ),
    );
    await tester.tap(reshareButton);
    await tester.pump();
    expect(calls.reshared, [1]);
  });

  testWidgets('no Reshare when not allowed or with the flag off', (
    tester,
  ) async {
    await open(tester, canReshare: false);
    expect(reshareButton, findsNothing);
    await open(tester, enable: false);
    expect(reshareButton, findsNothing);
  });

  testWidgets('Reshare opens the editor with the original photo', (
    tester,
  ) async {
    await open(tester, injectReshare: false);
    await tester.tap(reshareButton);
    // Decoding and PNG encoding run on real async work.
    for (
      var i = 0;
      i < 20 && find.byType(StoryEditorScreen).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    final editor = tester.widget<StoryEditorScreen>(
      find.byType(StoryEditorScreen),
    );
    expect(editor.draft.reshareOfStoryId, 1);
    expect(editor.draft.image.width, greaterThan(0));
    expect(editor.draft.image.contentType, 'image/png');
  });

  testWidgets('reshared story header links to the original author', (
    tester,
  ) async {
    final calls = await open(
      tester,
      canReshare: false,
      resharedFrom: {
        'story_id': 40,
        'user': {'id': 9, 'name': 'Sara Adel', 'avatar_url': null},
      },
    );
    expect(find.text('12h • reshared from mention'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('story-reshared-from')));
    await tester.pump();
    expect(calls.opened, [9]);
  });

  testWidgets('flag off: a reshared story shows the plain time', (
    tester,
  ) async {
    await open(
      tester,
      enable: false,
      resharedFrom: {
        'story_id': 40,
        'user': {'id': 9, 'name': 'Sara Adel', 'avatar_url': null},
      },
    );
    expect(find.textContaining('reshared from'), findsNothing);
    expect(find.byKey(const ValueKey('story-reshared-from')), findsNothing);
  });
}
