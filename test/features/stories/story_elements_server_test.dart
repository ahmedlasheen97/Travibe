import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/screens/story_viewer_screen.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';
import 'package:travibe/features/stories/data/story_elements.dart';

import 'fixtures.dart';
import 'story_viewer_test.dart' show ViewerRepo, viewerDetail, viewerGroup;

/// `GET /stories/19` `elements` from the production API (2026-11-18), for a
/// story posted with one hidden @ mention. The API trims strings, so the
/// zero-width `text` we sent came back as `null` (and keys are reordered).
/// Before the fix this failed the whole story: "This Story contains an
/// unsupported text document."
const serverHiddenMention = '''
{"id": "story-mentions", "text": null, "type": "text", "scale": 1, "style": {"padding": 8, "alignment": "center", "direction": "ltr", "font_size": 24, "color_argb": 4294967295, "font_family": "Plus Jakarta Sans", "font_weight": 600, "shadow_blur": 3, "reference_width": 390, "shadow_color_argb": 3707764736, "max_width_fraction": 0.8}, "content": "@lasheen1", "version": 1, "mentions": [{"user_id": 2, "username": "lasheen1"}], "position": {"x": 0.5, "y": 0.5}}
''';

Map<String, dynamic> server() =>
    jsonDecode(serverHiddenMention) as Map<String, dynamic>;

Map<String, dynamic> bubble(String id, String text) => StoryElements.encode([
  StoryTextLayer(id: id, text: text, center: const Offset(.5, .3)),
]).single;

void main() {
  test('the real server hidden-mention element decodes to nothing', () {
    expect(StoryElements.decode([server()]), isEmpty);
  });

  test('it does not hide the story\'s real text bubbles', () {
    final layers = StoryElements.decode([
      bubble('t1', 'Coffee with @lasheen1'),
      server(),
    ]);
    expect(layers, hasLength(1));
    expect((layers.single as StoryTextLayer).text, 'Coffee with @lasheen1');
  });

  test('the hidden element is skipped however the text comes back', () {
    for (final text in <Object?>[null, '', '  ', '​', '﻿', '@x']) {
      final element = server()..['text'] = text;
      expect(StoryElements.decode([element]), isEmpty, reason: '$text');
    }
    expect(StoryElements.decode([server()..remove('text')]), isEmpty);
  });

  test('blank text from any element draws nothing', () {
    for (final text in <Object?>[null, '', ' \n', '​⁠']) {
      expect(
        StoryElements.decode([bubble('t', 'x')..['text'] = text]),
        isEmpty,
      );
    }
    expect(StoryElements.decode([bubble('t', 'x')..remove('text')]), isEmpty);
  });

  test('one bad element is skipped; the rest of the story still renders', () {
    final bad = <Object?>[
      'not an object',
      bubble('v', 'x')..['version'] = 2,
      bubble('s', 'x')..['type'] = 'sticker',
      bubble('n', 'x')..['text'] = 42,
      bubble('i', 'x')..remove('id'),
      bubble('y', 'x')..['style'] = {'font_size': 30},
      bubble('p', 'x')..['position'] = {'x': 2, 'y': .5},
      bubble('q', 'x')..remove('position'),
      bubble('k', 'x')..['scale'] = 0,
      bubble('good', 'dup'),
    ];
    final layers = StoryElements.decode([
      bubble('good', 'Kept'),
      ...bad,
      server(),
    ]);
    expect(layers.map((l) => l.id), ['good']);
    expect((layers.single as StoryTextLayer).text, 'Kept');
  });

  testWidgets('viewer opens a story carrying the real server element', (
    tester,
  ) async {
    ScreenUtil.configure(
      data: const MediaQueryData(size: Size(390, 844)),
      designSize: const Size(390, 844),
      minTextAdapt: false,
      splitScreenMode: false,
    );
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('server-elements');
    addTearDown(PreferencesManager().clear);
    final repo = ViewerRepo()
      ..handler = (id) async => StoryDetail.fromJson(
        viewerDetail(id, elements: [bubble('t1', 'Hello'), server()])
          ..['mentions'] = [
            {
              'handle': 'lasheen1',
              'user': {'id': 2, 'username': 'lasheen1'},
            },
          ],
      );
    final photo = MemoryImage(photoBytes());
    await tester.pumpWidget(
      MaterialApp(
        home: StoryViewerScreen(
          groups: [
            viewerGroup(7, [1]),
          ],
          initialAuthorId: 7,
          repo: repo,
          imageProvider: (_) => photo,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('unsupported'), findsNothing);
    expect(find.byKey(const ValueKey('story-viewer-skip')), findsNothing);
    expect(find.byKey(const ValueKey('story-text-bubble')), findsOneWidget);
    expect(find.text('Hello', findRichText: true), findsOneWidget);
  });
}
