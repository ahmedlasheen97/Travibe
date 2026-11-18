import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';
import 'package:travibe/features/stories/data/story_elements.dart';
import 'package:travibe/features/stories/widgets/story_layer_geometry.dart';

import 'fixtures.dart';

Map<String, dynamic> element(String id, Object? text) => {
  'version': 1,
  'id': id,
  'type': 'text',
  'text': text,
  'position': {'x': .5, 'y': .5},
  'scale': 1,
  'style': StoryElements.style,
};

void main() {
  group('decode (text comes back exactly as sent)', () {
    test('empty, whitespace and zero-width-only text draws no bubble', () {
      final layers = StoryElements.decode([
        element('a', ''),
        element('b', '   '),
        element('c', '​'),
        element('d', '​ \n'),
        element('e', null),
      ]);
      expect(layers, isEmpty);
    });

    test('leading and trailing spaces are kept', () {
      final layers = StoryElements.decode([
        element('a', '  hi @sara  '),
        element('b', ' x'),
      ]);
      expect(layers.map((l) => (l as StoryTextLayer).text), [
        '  hi @sara  ',
        ' x',
      ]);
    });

    test(
      'an old story with the "\\u200B" mentions element shows no @names',
      () {
        final layers = StoryElements.decode([
          element('t', 'Coffee'),
          legacyMentionsElement(const [
            StoryMentionedUser(id: 5, username: 'sara'),
          ]),
        ]);
        expect(layers.map((l) => (l as StoryTextLayer).text), ['Coffee']);
      },
    );
  });

  group('bubble rendering', () {
    Future<(StoryTextGeometry, RenderParagraph)> pump(
      WidgetTester tester,
      String text,
    ) async {
      final geometry = StoryTextGeometry(
        StoryTextLayer(id: 't', text: text),
        const Size(390, 844),
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox.fromSize(
              size: geometry.size,
              child: geometry.content(),
            ),
          ),
        ),
      );
      return (
        geometry,
        tester.renderObject<RenderParagraph>(find.byType(RichText)),
      );
    }

    for (final text in ['  @sara  ', 'hi @sara   ', '   hi @sara']) {
      testWidgets('"$text": spaces draw where typed; taps line up', (
        tester,
      ) async {
        final (geometry, paragraph) = await pump(tester, text);
        expect(geometry.lines, 1);
        // Same number of characters: mention offsets still match the text.
        expect(paragraph.text.toPlainText().length, text.length);
        // Spaces aren't hung: the laid-out text fills the bubble on both sides.
        final whole = paragraph
            .getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: text.length),
            )
            .map((b) => b.toRect())
            .reduce((a, b) => a.expandToInclude(b));
        expect(whole.left, moreOrLessEquals(0));
        expect(whole.right, moreOrLessEquals(paragraph.size.width));
        // Tapping the drawn @sara resolves it, at the drawn rect.
        final at = text.indexOf('@');
        final drawn = paragraph
            .getBoxesForSelection(
              TextSelection(baseOffset: at, extentOffset: at + 5),
            )
            .first
            .toRect()
            .shift(geometry.padding.topLeft);
        final hit = geometry.mentionAt(drawn.center)!;
        expect(hit.$1, 'sara');
        expect(hit.$2, drawn);
      });
    }
  });
}
