import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/screen_util.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/stories/data/mentions_repo.dart';
import 'package:travibe/features/stories/cubit/story_editor_cubit.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';
import 'package:travibe/features/stories/data/story_elements.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/screens/story_editor_screen.dart';
import 'package:travibe/features/stories/widgets/story_canvas.dart';

import 'fixtures.dart';

PublicUserModel user(int id, String? username) => PublicUserModel(
  id: '$id',
  name: 'User $id',
  username: username,
  isFollowing: false,
  isBlocked: false,
  followersCount: 0,
  followingCount: 0,
);

/// `/mentions/suggestions` fake: no query lists [followed]; a query is a
/// case-insensitive prefix match over [everyone].
class FakeMentionsRepo extends MentionsRepo {
  final queries = <String?>[];
  List<PublicUserModel> followed = [user(5, 'sara'), user(7, 'omar')];
  List<PublicUserModel> everyone = [
    user(5, 'sara'),
    user(7, 'omar'),
    user(8, 'sarah.k'),
  ];
  @override
  Future<List<PublicUserModel>> suggestions({
    String? q,
    int perPage = 20,
  }) async {
    final term = (q ?? '').replaceFirst('@', '').toLowerCase();
    queries.add(term.isEmpty ? null : term);
    if (term.isEmpty) return followed;
    return everyone
        .where((u) => u.username!.toLowerCase().startsWith(term))
        .toList();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('StoryEditorCubit stickers and strokes', () {
    test('emoji sticker add, move/scale/rotate and delete', () {
      final cubit = StoryEditorCubit(draft());
      addTearDown(cubit.close);
      expect(cubit.addEmoji('🌍'), isTrue);
      expect(cubit.addEmoji('🔥'), isTrue);
      final first = cubit.state.layers.first as StoryEmojiLayer;
      expect(first.emoji, '🌍');
      expect(first.center, const Offset(.5, .5));
      cubit.commitTransform(first.id, const Offset(.2, .8), 2.5, rotation: .7);
      final moved = cubit.state.layers.first as StoryEmojiLayer;
      expect(moved.id, first.id);
      expect(moved.center, const Offset(.2, .8));
      expect(moved.scale, 2.5);
      expect(moved.rotation, .7);
      expect(cubit.state.hasFlattenedContent, isTrue);
      cubit.removeLayer(first.id);
      expect(cubit.state.layers.single, isA<StoryEmojiLayer>());
      expect((cubit.state.layers.single as StoryEmojiLayer).emoji, '🔥');
      expect(cubit.addEmoji('  '), isFalse);
    });

    test('emoji cap is separate from the 50 element cap', () {
      final cubit = StoryEditorCubit(draft());
      addTearDown(cubit.close);
      for (var i = 0; i < StoryEditorCubit.maxEmojis; i++) {
        expect(cubit.addEmoji('😀'), isTrue);
      }
      expect(cubit.addEmoji('😀'), isFalse);
      expect(cubit.elementCount, 0);
      cubit.saveText('Still allowed');
      expect(cubit.elementCount, 1);
    });

    test('mention requires a username and a numeric id', () {
      final cubit = StoryEditorCubit(draft());
      addTearDown(cubit.close);
      expect(cubit.addMention(user(6, null)), isFalse);
      expect(cubit.addMention(user(5, 'sara')), isTrue);
      final mention = cubit.state.layers.single as StoryMentionLayer;
      expect(mention.text, '@sara');
      expect(mention.userId, 5);
      expect(mention.style, StoryMentionStyle.light);
      // Mentions are elements, not flattened content.
      expect(cubit.state.hasFlattenedContent, isFalse);
    });

    test('syncMentions keeps, removes and adds stickers to match', () {
      final cubit = StoryEditorCubit(draft());
      addTearDown(cubit.close);
      expect(cubit.syncMentions([user(5, 'sara'), user(7, 'omar')]), 0);
      final sara = cubit.state.layers.whereType<StoryMentionLayer>().first;
      expect(
        cubit.state.layers.whereType<StoryMentionLayer>().map((l) => l.text),
        ['@sara', '@omar'],
      );
      // New stickers are stacked, not on top of each other.
      final centers = cubit.state.layers.map((l) => l.center).toSet();
      expect(centers, hasLength(2));
      cubit.commitTransform(sara.id, const Offset(.2, .3), 2);
      // Uncheck omar, keep sara (with her move and scale), add one without a
      // username (rejected) and a new one.
      expect(
        cubit.syncMentions([user(5, 'sara'), user(6, null), user(8, 'nour')]),
        1,
      );
      final layers = cubit.state.layers.cast<StoryMentionLayer>();
      expect(layers.map((l) => l.text), ['@sara', '@nour']);
      expect(layers.first.id, sara.id);
      expect(layers.first.center, const Offset(.2, .3));
      expect(layers.first.scale, 2);
      expect(cubit.mentionedUsers.map((u) => u.id), [5, 8]);
      expect(cubit.state.allowReshare, isTrue);
      cubit.setAllowReshare(false);
      expect(cubit.state.allowReshare, isFalse);
    });

    test(
      'allow_reshare and reshare_of_story_id are sent only behind the flag',
      () {
        final off = draft().withAllowReshare(false);
        expect(
          CreateStoryRequest(mediaId: 3, draft: off).toJson().keys,
          isNot(contains('allow_reshare')),
        );
        final on = CreateStoryRequest(
          mediaId: 3,
          draft: off,
          includeReshare: true,
        ).toJson();
        expect(on['allow_reshare'], isFalse);
        expect(on.containsKey('reshare_of_story_id'), isFalse);
        final reshare = StoryEditorDraft(
          image: draft().image,
          reshareOfStoryId: 9,
        );
        expect(
          CreateStoryRequest(
            mediaId: 3,
            draft: reshare,
            includeReshare: true,
          ).toJson()['reshare_of_story_id'],
          9,
        );
      },
    );

    test('text keeps rotation 0 even if a rotation is committed', () {
      final cubit = StoryEditorCubit(draft());
      addTearDown(cubit.close);
      cubit.saveText('Hi');
      final id = cubit.state.layers.single.id;
      cubit.commitTransform(id, const Offset(.3, .3), 1.2, rotation: 1);
      expect(cubit.state.layers.single.rotation, 0);
      expect(cubit.state.layers.single, isA<StoryTextLayer>());
    });

    test('strokes append and undo removes only the last one', () {
      final cubit = StoryEditorCubit(draft());
      addTearDown(cubit.close);
      final a = StoryStroke(
        points: const [Offset(.1, .1), Offset(.2, .2)],
        colorArgb: 0xFFFFFFFF,
        width: .02,
      );
      final b = StoryStroke(
        points: const [Offset(.5, .5)],
        colorArgb: 0xFFE53935,
        width: .05,
      );
      cubit.addStroke(a);
      cubit.addStroke(b);
      cubit.addStroke(StoryStroke(points: const [], colorArgb: 0, width: .1));
      expect(cubit.state.strokes, [a, b]);
      cubit.undoStroke();
      expect(cubit.state.strokes, [a]);
      cubit.undoStroke();
      cubit.undoStroke();
      expect(cubit.state.strokes, isEmpty);
      expect(cubit.state.hasFlattenedContent, isFalse);
    });
  });

  group('mention payload', () {
    StoryEditorDraft composed() {
      final cubit = StoryEditorCubit(draft());
      cubit.saveText('Paris');
      cubit.addMention(user(5, 'sara'));
      cubit.addEmoji('🌍');
      cubit.addStroke(
        StoryStroke(
          points: const [Offset(.1, .1)],
          colorArgb: 0xFFFFFFFF,
          width: .02,
        ),
      );
      final mention = cubit.state.layers[1];
      cubit.commitTransform(
        mention.id,
        const Offset(.3, .6),
        1.5,
        rotation: .25,
      );
      final state = cubit.state;
      cubit.close();
      return state;
    }

    test('mention is a v1 text element; emojis and strokes are not sent', () {
      final json = CreateStoryRequest(mediaId: 19, draft: composed()).toJson();
      final elements = json['elements'] as List;
      expect(elements, hasLength(2));
      final mention = elements[1] as Map<String, dynamic>;
      expect(mention['type'], 'text');
      // The API parses @username out of text elements and notifies the user.
      expect(mention['text'], '@sara');
      expect(mention['position'], {'x': .3, 'y': .6});
      expect(mention['scale'], 1.5);
      expect(mention['rotation'], .25);
      expect(mention['mention'], {
        'user_id': 5,
        'username': 'sara',
        'style': 'light',
      });
      // Identical v1 style keeps older app builds able to render it.
      expect(mention['style'], StoryElements.style);
      expect(elements.first['text'], 'Paris');
      expect((elements.first as Map).containsKey('mention'), isFalse);
      expect(jsonEncode(json), isNot(contains('🌍')));
    });

    test('decode round-trips mentions and keeps plain text decoding', () {
      final encoded = StoryElements.encode(composed().layers);
      final restored = StoryElements.decode(jsonDecode(jsonEncode(encoded)));
      expect(restored, hasLength(2));
      expect((restored.first as StoryTextLayer).text, 'Paris');
      final mention = restored[1] as StoryMentionLayer;
      expect(mention.userId, 5);
      expect(mention.username, 'sara');
      expect(mention.style, StoryMentionStyle.light);
      expect(mention.rotation, .25);
      expect(mention.center, const Offset(.3, .6));
    });

    test('mismatched mention metadata degrades to plain text', () {
      final encoded = StoryElements.encode(composed().layers);
      encoded[1]['text'] = '@someone_else';
      final restored = StoryElements.decode(jsonDecode(jsonEncode(encoded)));
      expect(restored[1], isA<StoryTextLayer>());
      expect((restored[1] as StoryTextLayer).text, '@someone_else');
    });

    test(
      'StoryDetail resolves mentions case-insensitively, tolerating junk',
      () {
        final mentions = StoryMention.listFrom([
          {
            'handle': 'Sara',
            'user': {'id': 5, 'username': 'sara'},
          },
          {'handle': 'bad'},
          'junk',
        ]);
        expect(mentions, hasLength(1));
        expect(mentions.single.handle, 'sara');
        expect(StoryMention.listFrom(null), isEmpty);
      },
    );
  });

  group('editor screen', () {
    Future<void> show(
      WidgetTester tester, {
      MentionsRepo? search,
      bool enableReshare = false,
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        withScreenUtil(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: StoryEditorScreen(
              draft: draft(),
              mentionsRepo: search ?? FakeMentionsRepo(),
              enableReshare: enableReshare,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    StoryEditorDraft current(WidgetTester tester) =>
        tester.widget<StoryCanvas>(find.byType(StoryCanvas)).draft;

    // Scoped to the sheet: placed stickers also render the same emoji text.
    Finder pickerEmoji(String emoji) => find
        .descendant(
          of: find.byKey(const ValueKey('story-emoji-sheet')),
          matching: find.text(emoji),
        )
        .first;

    testWidgets('tool column has Aa, @, emoji and draw; no location', (
      tester,
    ) async {
      await show(tester);
      for (final key in [
        'story-text-tool',
        'story-mention-tool',
        'story-emoji-tool',
        'story-draw-tool',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget);
      }
      expect(find.byIcon(Icons.location_on_outlined), findsNothing);
      expect(find.byTooltip('Location — coming soon'), findsNothing);
    });

    testWidgets('emoji sheet adds a sticker that moves and drags to trash', (
      tester,
    ) async {
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('story-emoji-tool')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('story-emoji-sheet')), findsOneWidget);
      await tester.tap(pickerEmoji('😀'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('story-emoji-sheet')), findsNothing);
      final sticker = current(tester).layers.single as StoryEmojiLayer;
      expect(sticker.emoji, '😀');
      final finder = find.byKey(ValueKey('story-layer-${sticker.id}'));

      // Move: drop away from the trash target.
      var gesture = await tester.startGesture(tester.getCenter(finder));
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      expect(find.byKey(const ValueKey('story-delete-target')), findsOneWidget);
      await gesture.moveBy(const Offset(-80, -100));
      await gesture.up();
      await tester.pumpAndSettle();
      final moved = current(tester).layers.single;
      expect(moved.id, sticker.id);
      expect(moved.center.dx, lessThan(.5));
      expect(moved.center.dy, lessThan(.5));

      // Delete: drop onto the trash target.
      gesture = await tester.startGesture(tester.getCenter(finder));
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      final trash = tester.getCenter(
        find.byKey(const ValueKey('story-delete-target')),
      );
      await gesture.moveTo(trash);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(current(tester).layers, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('multiple emojis can be added', (tester) async {
      await show(tester);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byKey(const ValueKey('story-emoji-tool')));
        await tester.pumpAndSettle();
        await tester.tap(pickerEmoji('😀'));
        await tester.pumpAndSettle();
      }
      expect(current(tester).layers.whereType<StoryEmojiLayer>(), hasLength(2));
    });

    Finder check(int id) => find.byKey(ValueKey('story-mention-check-$id'));
    Finder row(int id) => find.byKey(ValueKey('story-mention-user-$id'));
    bool addEnabled(WidgetTester tester) => tester
        .widget<FilledButton>(find.byKey(const ValueKey('story-mention-add')))
        .enabled;

    testWidgets('mention sheet: followed people, search, multi-select, Add', (
      tester,
    ) async {
      final search = FakeMentionsRepo();
      await show(tester, search: search);
      await tester.tap(find.byKey(const ValueKey('story-mention-tool')));
      await tester.pumpAndSettle();
      expect(find.text('Mention'), findsOneWidget);
      expect(find.text('Search people'), findsOneWidget);
      // Opening lists the people you follow (no query).
      expect(search.queries, [null]);
      expect(row(5), findsOneWidget);
      expect(row(7), findsOneWidget);
      expect(find.text('@sara'), findsOneWidget);
      // Reshare toggle is behind the flag.
      expect(find.byKey(const ValueKey('story-reshare-toggle')), findsNothing);
      expect(addEnabled(tester), isFalse);

      await tester.enterText(
        find.byKey(const ValueKey('story-mention-search')),
        '@sar',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(search.queries.last, 'sar');
      expect(row(7), findsNothing);
      await tester.tap(row(5));
      await tester.tap(row(8));
      await tester.pump();
      expect(addEnabled(tester), isTrue);
      await tester.tap(find.byKey(const ValueKey('story-mention-add')));
      await tester.pumpAndSettle();
      final mentions = current(tester).layers.cast<StoryMentionLayer>();
      expect(mentions.map((m) => m.text), ['@sara', '@sarah.k']);
      // Figma glass bubble with an orange, full @username.
      expect(
        find.byKey(const ValueKey('story-mention-sticker')),
        findsNWidgets(2),
      );
      final label = tester.widget<Text>(find.text('@sarah.k'));
      expect(label.style!.color, DarkColors.primaryColor);
      expect(label.maxLines, isNull);
      expect(label.overflow, isNull);
      // Tapping a sticker in the editor no longer restyles it.
      final first = mentions.first;
      await tester.tap(find.byKey(ValueKey('story-layer-${first.id}')));
      await tester.pumpAndSettle();
      final after = current(tester).layers.first as StoryMentionLayer;
      expect(after.id, first.id);
      expect(after.style, first.style);
      expect(after.center, first.center);
      expect(after.scale, first.scale);
    });

    test('sticker bubble grows to fit the username and wraps long ones', () {
      const canvas = Size(390, 844);
      StoryMentionGeometry geometry(String username) => StoryMentionGeometry(
        StoryMentionLayer(id: 'm', userId: 1, username: username),
        canvas,
      );
      final short = geometry('sara');
      final longer = geometry('sarakhaled12');
      expect(short.lines, 1);
      expect(longer.lines, 1);
      expect(longer.size.width, greaterThan(short.size.width));
      // One line: a pill.
      expect(short.radius, short.size.height / 2);
      final huge = geometry('a_very_long_username_that_keeps_going_and_going');
      expect(huge.lines, greaterThan(1));
      expect(huge.size.height, greaterThan(short.size.height));
      expect(huge.size.width, lessThanOrEqualTo(canvas.width * 0.8));
      expect(short.style.color, DarkColors.primaryColor);
    });

    testWidgets('reopening shows the selection checked; uncheck removes it', (
      tester,
    ) async {
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('story-mention-tool')));
      await tester.pumpAndSettle();
      await tester.tap(row(5));
      await tester.tap(row(7));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('story-mention-add')));
      await tester.pumpAndSettle();
      expect(current(tester).layers, hasLength(2));

      await tester.tap(find.byKey(const ValueKey('story-mention-tool')));
      await tester.pumpAndSettle();
      Color? fill(int id) =>
          ((tester
                      .widget<AnimatedContainer>(
                        find.descendant(
                          of: check(id),
                          matching: find.byType(AnimatedContainer),
                        ),
                      )
                      .decoration
                  as BoxDecoration)
              .color);
      expect(fill(5), DarkColors.primaryColor);
      expect(fill(7), DarkColors.primaryColor);
      expect(addEnabled(tester), isTrue);
      await tester.tap(row(7));
      await tester.pump();
      expect(fill(7), Colors.transparent);
      await tester.tap(find.byKey(const ValueKey('story-mention-add')));
      await tester.pumpAndSettle();
      expect(
        current(tester).layers.cast<StoryMentionLayer>().map((m) => m.text),
        ['@sara'],
      );
    });

    testWidgets('with the flag on, the sheet toggle sets allowReshare', (
      tester,
    ) async {
      await show(tester, enableReshare: true);
      await tester.tap(find.byKey(const ValueKey('story-mention-tool')));
      await tester.pumpAndSettle();
      expect(
        find.text('People you mention can reshare this story'),
        findsOneWidget,
      );
      final toggle = find.byKey(const ValueKey('story-reshare-toggle'));
      expect(tester.widget<Switch>(toggle).value, isTrue);
      await tester.tap(toggle);
      await tester.tap(row(5));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('story-mention-add')));
      await tester.pumpAndSettle();
      expect(current(tester).allowReshare, isFalse);
    });

    testWidgets('draw mode hides tools, records strokes, undo and done', (
      tester,
    ) async {
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('story-draw-tool')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('story-text-tool')), findsNothing);
      expect(find.byKey(const ValueKey('story-emoji-tool')), findsNothing);
      expect(find.byKey(const ValueKey('story-post')), findsNothing);
      expect(find.byKey(const ValueKey('story-audience')), findsNothing);
      expect(find.byKey(const ValueKey('story-draw-controls')), findsOneWidget);
      for (final color in StoryEditorScreenColors.brush) {
        expect(
          find.byKey(ValueKey('story-brush-${color.toARGB32()}')),
          findsOneWidget,
        );
      }
      IconButton undo() => tester.widget<IconButton>(
        find.byKey(const ValueKey('story-draw-undo')),
      );
      expect(undo().onPressed, isNull);

      const red = Color(0xFFE53935);
      await tester.tap(find.byKey(ValueKey('story-brush-${red.toARGB32()}')));
      await tester.pump();
      await tester.dragFrom(const Offset(80, 300), const Offset(120, 60));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('story-brush-${Colors.white.toARGB32()}')),
      );
      await tester.pump();
      await tester.dragFrom(const Offset(80, 450), const Offset(150, 0));
      await tester.pumpAndSettle();
      final strokes = current(tester).strokes;
      expect(strokes, hasLength(2));
      expect(strokes.first.colorArgb, red.toARGB32());
      expect(strokes.last.colorArgb, Colors.white.toARGB32());
      expect(strokes.first.points.length, greaterThan(1));
      expect(
        strokes.every(
          (s) => s.points.every(
            (p) => p.dx >= 0 && p.dx <= 1 && p.dy >= 0 && p.dy <= 1,
          ),
        ),
        isTrue,
      );

      await tester.tap(find.byKey(const ValueKey('story-draw-undo')));
      await tester.pumpAndSettle();
      expect(current(tester).strokes, hasLength(1));
      expect(current(tester).strokes.single.colorArgb, red.toARGB32());

      await tester.tap(find.byKey(const ValueKey('story-draw-done')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('story-text-tool')), findsOneWidget);
      expect(find.byKey(const ValueKey('story-post')), findsOneWidget);
      expect(find.byKey(const ValueKey('story-drawing-surface')), findsNothing);
      expect(current(tester).strokes, hasLength(1));
      // Strokes render inside the exported content boundary.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('story-render-content')),
          matching: find.byKey(const ValueKey('story-strokes')),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
