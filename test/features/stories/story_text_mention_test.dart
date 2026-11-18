import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';
import 'package:travibe/features/stories/screens/story_editor_screen.dart';
import 'package:travibe/features/stories/widgets/story_canvas.dart';
import 'package:travibe/features/stories/widgets/story_mention_text.dart';

import '../../helpers/screen_util.dart';
import 'fixtures.dart';
import 'story_editor_tools_test.dart' show FakeMentionsRepo;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('mention text helpers', () {
    test('finds @handles but not emails or trailing dots', () {
      final ranges = storyMentionRanges('Hi @sara. mail a@b.com @sarah.k!');
      expect(
        [
          for (final r in ranges)
            'Hi @sara. mail a@b.com @sarah.k!'.substring(r.start, r.end),
        ],
        ['@sara', '@sarah.k'],
      );
    });

    test('query at the caret and insertion', () {
      const typing = TextEditingValue(
        text: 'Best coffe with @sa',
        selection: TextSelection.collapsed(offset: 19),
      );
      final query = storyMentionQueryAt(typing)!;
      expect(query.query, 'sa');
      expect(query.start, 16);
      final inserted = insertStoryMention(typing, query, 'sarakhaled12');
      expect(inserted.text, 'Best coffe with @sarakhaled12 ');
      expect(inserted.selection.baseOffset, inserted.text.length);
      expect(storyMentionQueryAt(inserted), isNull);
      // An email is not a mention query.
      expect(
        storyMentionQueryAt(
          const TextEditingValue(
            text: 'me@ex',
            selection: TextSelection.collapsed(offset: 5),
          ),
        ),
        isNull,
      );
    });

    test('only the handle is orange', () {
      final span = storyMentionTextSpan('Hi @sara', const TextStyle());
      final parts = span.children!.cast<TextSpan>();
      expect(parts.map((p) => p.text), ['Hi ', '@sara']);
      expect(parts.first.style?.color, isNull);
      expect(parts.last.style!.color, DarkColors.primaryColor);
    });
  });

  group('typing @ in story text', () {
    Future<FakeMentionsRepo> show(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeMentionsRepo();
      await tester.pumpWidget(
        withScreenUtil(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: StoryEditorScreen(draft: draft(), mentionsRepo: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('story-text-tool')));
      await tester.pumpAndSettle();
      return repo;
    }

    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(
        find.byKey(const ValueKey('story-text-input')),
        text,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }

    StoryEditorDraft current(WidgetTester tester) =>
        tester.widget<StoryCanvas>(find.byType(StoryCanvas)).draft;

    testWidgets(
      'suggestions filter as you type; tap inserts orange @username',
      (tester) async {
        final repo = await show(tester);
        await type(tester, 'Best coffee');
        expect(
          find.byKey(const ValueKey('story-mention-suggestions')),
          findsNothing,
        );
        expect(repo.queries, isEmpty);

        await type(tester, 'Best coffee with @sa');
        expect(repo.queries.last, 'sa');
        expect(
          find.byKey(const ValueKey('story-mention-suggestions')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('story-mention-suggestion-5')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('story-mention-suggestion-8')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('story-mention-suggestion-7')),
          findsNothing,
        );
        // Figma: the reshare toggle sits under the suggestions.
        expect(
          find.byKey(const ValueKey('story-reshare-toggle')),
          findsOneWidget,
        );

        await type(tester, 'Best coffee with @sarah');
        expect(repo.queries.last, 'sarah');
        expect(
          find.byKey(const ValueKey('story-mention-suggestion-5')),
          findsNothing,
        );
        await tester.tap(
          find.byKey(const ValueKey('story-mention-suggestion-8')),
        );
        await tester.pumpAndSettle();
        final field = tester.widget<TextField>(
          find.byKey(const ValueKey('story-text-input')),
        );
        expect(field.controller!.text, 'Best coffee with @sarah.k ');
        expect(
          find.byKey(const ValueKey('story-mention-suggestions')),
          findsNothing,
        );
        final span = field.controller!.buildTextSpan(
          context: tester.element(find.byType(TextField)),
          withComposing: false,
        );
        final mention = span.children!.cast<TextSpan>().firstWhere(
          (s) => s.text == '@sarah.k',
        );
        expect(mention.style!.color, DarkColors.primaryColor);

        await tester.tap(find.byKey(const ValueKey('story-text-done')));
        await tester.pumpAndSettle();
        final layer = current(tester).layers.single as StoryTextLayer;
        expect(layer.text, 'Best coffee with @sarah.k ');
      },
    );

    testWidgets(
      'with the flag on, the same reshare toggle shows while typing',
      (tester) async {
        await show(tester);
        await type(tester, '@om');
        final toggle = find.byKey(const ValueKey('story-reshare-toggle'));
        expect(toggle, findsOneWidget);
        expect(tester.widget<Switch>(toggle).value, isTrue);
        await tester.tap(toggle);
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('story-text-done')));
        await tester.pumpAndSettle();
        expect(current(tester).allowReshare, isFalse);
        // The Mention sheet opens with the same setting.
        await tester.tap(find.byKey(const ValueKey('story-mention-tool')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Switch>(
                find.byKey(const ValueKey('story-reshare-toggle')),
              )
              .value,
          isFalse,
        );
      },
    );
  });
}
