import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/search/data/search_repo.dart';
import 'package:travibe/features/search/data/users_page_model.dart';
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

class FakeSearchRepo extends SearchRepo {
  final queries = <String>[];
  List<PublicUserModel> users = [user(5, 'sara'), user(6, null)];
  @override
  Future<UsersPageModel> searchUsers(String query, {int page = 1}) async {
    queries.add(query);
    return UsersPageModel(
      users: users,
      currentPage: 1,
      lastPage: 1,
      total: users.length,
    );
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

    test('mention requires a username and a numeric id; tap cycles style', () {
      final cubit = StoryEditorCubit(draft());
      addTearDown(cubit.close);
      expect(cubit.addMention(user(6, null)), isFalse);
      expect(cubit.addMention(user(5, 'sara')), isTrue);
      final mention = cubit.state.layers.single as StoryMentionLayer;
      expect(mention.text, '@sara');
      expect(mention.userId, 5);
      expect(mention.style, StoryMentionStyle.light);
      cubit.cycleMentionStyle(mention.id);
      expect(
        (cubit.state.layers.single as StoryMentionLayer).style,
        StoryMentionStyle.dark,
      );
      // Mentions are elements, not flattened content.
      expect(cubit.state.hasFlattenedContent, isFalse);
    });

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
      cubit.cycleMentionStyle(mention.id);
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
        'style': 'dark',
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
      expect(mention.style, StoryMentionStyle.dark);
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
    Future<void> show(WidgetTester tester, {SearchRepo? search}) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: StoryEditorScreen(draft: draft(), searchRepo: search),
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

    testWidgets('mention sheet searches and adds a tappable @username', (
      tester,
    ) async {
      final search = FakeSearchRepo();
      await show(tester, search: search);
      await tester.tap(find.byKey(const ValueKey('story-mention-tool')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('story-mention-search')),
        'sa',
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(search.queries, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('story-mention-search')),
        '@sar',
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('story-mention-loading')),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(search.queries, ['sar']);
      // A user with no username cannot be mentioned and is not listed.
      expect(find.byKey(const ValueKey('story-mention-user-6')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('story-mention-user-5')));
      await tester.pumpAndSettle();
      final mention = current(tester).layers.single as StoryMentionLayer;
      expect(mention.text, '@sara');
      expect(find.text('@sara'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('story-layer-${mention.id}')));
      await tester.pumpAndSettle();
      expect(
        (current(tester).layers.single as StoryMentionLayer).style,
        StoryMentionStyle.dark,
      );
      expect(find.byKey(const ValueKey('story-mention-dark')), findsOneWidget);
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
