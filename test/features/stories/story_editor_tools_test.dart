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

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/stories/data/story_audience.dart';
import 'fixtures.dart';
import 'story_reshare_test.dart' show currentUser;

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

    test('setMentions keeps picked people hidden: nothing is drawn', () {
      final cubit = StoryEditorCubit(draft());
      addTearDown(cubit.close);
      expect(cubit.setMentions([user(5, 'sara'), user(7, 'omar')]), 0);
      expect(cubit.state.layers, isEmpty);
      expect(cubit.state.mentions.map((m) => m.username), ['sara', 'omar']);
      // Sent as mention_user_ids: no element.
      expect(cubit.elementCount, 0);
      // No username (rejected), duplicates collapse, unchecked are dropped.
      expect(
        cubit.setMentions([
          user(5, 'sara'),
          user(6, null),
          user(5, 'sara'),
          user(8, 'nour'),
        ]),
        1,
      );
      expect(cubit.state.mentions.map((m) => m.id), [5, 8]);
      expect(cubit.state.hasFlattenedContent, isFalse);
      expect(cubit.setMentions(const []), 0);
      expect(cubit.state.mentions, isEmpty);
      expect(cubit.elementCount, 0);
      expect(cubit.state.allowReshare, isTrue);
      cubit.setAllowReshare(false);
      expect(cubit.state.allowReshare, isFalse);
    });

    test('at most 10 mentions are kept (the API stores 10)', () {
      final cubit = StoryEditorCubit(draft());
      addTearDown(cubit.close);
      final many = [for (var i = 1; i <= 12; i++) user(i, 'user$i')];
      expect(cubit.setMentions(many), 2);
      expect(cubit.state.mentions, hasLength(StoryElements.maxMentions));
    });

    test('allow_mention_reshare is sent only for an eligible story', () {
      Map<String, dynamic> body(StoryEditorDraft d) => CreateStoryRequest(
        mediaId: 3,
        draft: d,
        allowMentionReshare: d.sendsMentionReshare,
      ).toJson();
      final eligible = draft().withAccountIsPublic(true);
      expect(eligible.canAllowMentionReshare, isTrue);
      expect(body(eligible)['allow_mention_reshare'], isTrue);
      // Toggle off, private/unknown account, or followers-only: no key.
      for (final d in [
        eligible.withAllowReshare(false),
        draft(),
        eligible.withAudience(StoryAudience.followers),
      ]) {
        expect(body(d).keys, isNot(contains('allow_mention_reshare')));
      }
      expect(draft().canAllowMentionReshare, isFalse);
      expect(
        eligible.withAudience(StoryAudience.followers).canAllowMentionReshare,
        isFalse,
      );
      // Even if asked, a followers story never sends it (the API 422s).
      expect(
        CreateStoryRequest(
          mediaId: 3,
          draft: draft().withAudience(StoryAudience.followers),
          allowMentionReshare: true,
        ).toJson().keys,
        isNot(contains('allow_mention_reshare')),
      );
      for (final key in ['allow_reshare', 'reshare_of_story_id']) {
        expect(body(eligible).keys, isNot(contains(key)));
      }
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
      cubit.saveText('Paris with @omar');
      cubit.setMentions([user(5, 'sara'), user(8, 'sarah.k')]);
      cubit.addEmoji('🌍');
      cubit.addStroke(
        StoryStroke(
          points: const [Offset(.1, .1)],
          colorArgb: 0xFFFFFFFF,
          width: .02,
        ),
      );
      final state = cubit.state;
      cubit.close();
      return state;
    }

    test('hidden mentions go in mention_user_ids, not an element', () {
      final json = CreateStoryRequest(mediaId: 19, draft: composed()).toJson();
      final elements = json['elements'] as List;
      // Aa text keeps its @username; the API parses it from `text`.
      expect(elements, hasLength(1));
      expect(elements.single['text'], 'Paris with @omar');
      expect(
        elements.where((e) => e['id'] == StoryElements.mentionsId),
        isEmpty,
      );
      expect(json['mention_user_ids'], [5, 8]);
      expect(jsonEncode(json), isNot(contains('🌍')));
      expect(jsonEncode(json), isNot(contains('\u200B')));
    });

    test('mention_user_ids is deduped, ordered and left out when empty', () {
      final dupes = draft().withMentions(const [
        StoryMentionedUser(id: 7, username: 'omar'),
        StoryMentionedUser(id: 5, username: 'sara'),
        StoryMentionedUser(id: 7, username: 'omar'),
      ]);
      expect(
        CreateStoryRequest(
          mediaId: 1,
          draft: dupes,
        ).toJson()['mention_user_ids'],
        [7, 5],
      );
      expect(
        CreateStoryRequest(
          mediaId: 1,
          draft: dupes,
          includeMentions: false,
        ).toJson(),
        isNot(contains('mention_user_ids')),
      );
      expect(
        CreateStoryRequest(mediaId: 1, draft: draft()).toJson(),
        isNot(contains('mention_user_ids')),
      );
      final eleven = draft().withMentions([
        for (var i = 1; i <= 11; i++)
          StoryMentionedUser(id: i, username: 'u$i'),
      ]);
      expect(
        () => CreateStoryRequest(mediaId: 1, draft: eleven).toJson(),
        throwsFormatException,
      );
    });

    test('hidden mentions no longer count towards the 50 elements', () {
      final cubit = StoryEditorCubit(draft());
      for (var i = 0; i < StoryEditorCubit.maxElements; i++) {
        cubit.saveText('t$i');
      }
      expect(cubit.setMentions([user(5, 'sara')]), 0);
      expect(cubit.state.mentions.single.id, 5);
      expect(cubit.elementCount, StoryEditorCubit.maxElements);
      cubit.close();
    });

    test('decode skips the old mentions element whatever its text', () {
      const sara = [StoryMentionedUser(id: 5, username: 'sara')];
      for (final text in ['\u200B', null, '', '  ', '@sara']) {
        final restored = StoryElements.decode([
          ...StoryElements.encode(composed().layers),
          legacyMentionsElement(sara, text: text),
        ]);
        expect(restored, hasLength(1), reason: 'text: $text');
        expect((restored.single as StoryTextLayer).text, 'Paris with @omar');
      }
    });

    test('stickers from earlier builds show as text with the @username', () {
      final legacy = [
        {
          'version': 1,
          'id': 'story-mention-1',
          'type': 'text',
          'text': '@sara',
          'position': {'x': .3, 'y': .6},
          'scale': 1.5,
          'style': StoryElements.style,
          'rotation': .25,
          'mention': {'user_id': 5, 'username': 'sara', 'style': 'dark'},
        },
      ];
      final restored = StoryElements.decode(legacy).single as StoryTextLayer;
      expect(restored.text, '@sara');
      expect(restored.center, const Offset(.3, .6));
      expect(restored.scale, 1.5);
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
    /// [private] null: no signed-in profile (privacy unknown).
    Future<void> show(
      WidgetTester tester, {
      MentionsRepo? search,
      bool? private = false,
      StoryAudience audience = StoryAudience.public,
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      CurrentUserCubit? user;
      if (private != null) {
        user = await currentUser(private: private);
        addTearDown(user.close);
      }
      Widget editor = StoryEditorScreen(
        draft: draft().withAudience(audience),
        mentionsRepo: search ?? FakeMentionsRepo(),
      );
      if (user != null) {
        editor = BlocProvider<CurrentUserCubit>.value(
          value: user,
          child: editor,
        );
      }
      await tester.pumpWidget(
        withScreenUtil(
          MaterialApp(theme: ThemeData.dark(useMaterial3: true), home: editor),
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

    Finder badge() => find.byKey(const ValueKey('story-mention-count'));
    Finder toggle() => find.byKey(const ValueKey('story-reshare-toggle'));

    testWidgets('@ = hidden mention: picked people, no sticker, count badge', (
      tester,
    ) async {
      final search = FakeMentionsRepo();
      await show(tester, search: search);
      expect(badge(), findsNothing);
      await tester.tap(find.byKey(const ValueKey('story-mention-tool')));
      await tester.pumpAndSettle();
      expect(find.text('Mention'), findsOneWidget);
      expect(find.text('Search people'), findsOneWidget);
      // Opening lists the people you follow (no query).
      expect(search.queries, [null]);
      expect(row(5), findsOneWidget);
      expect(row(7), findsOneWidget);
      expect(find.text('@sara'), findsOneWidget);
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

      // Nothing is placed on the story; the users are kept as mentions.
      expect(current(tester).layers, isEmpty);
      expect(find.text('@sara'), findsNothing);
      expect(current(tester).mentions.map((m) => m.username), [
        'sara',
        'sarah.k',
      ]);
      expect(
        find.descendant(of: badge(), matching: find.text('2')),
        findsOneWidget,
      );
      expect(find.byTooltip('Mentioned: @sara, @sarah.k'), findsOneWidget);
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
      expect(current(tester).mentions, hasLength(2));

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
      expect(current(tester).mentions.map((m) => m.username), ['sara']);
      expect(
        find.descendant(of: badge(), matching: find.text('1')),
        findsOneWidget,
      );
    });

    testWidgets('a picked user missing from suggestions still shows checked', (
      tester,
    ) async {
      final search = FakeMentionsRepo();
      await show(tester, search: search);
      await tester.tap(find.byKey(const ValueKey('story-mention-tool')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('story-mention-search')),
        'sarah',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(row(8));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('story-mention-add')));
      await tester.pumpAndSettle();
      // Not followed, so not in the no-query list; it is listed on top.
      await tester.tap(find.byKey(const ValueKey('story-mention-tool')));
      await tester.pumpAndSettle();
      expect(row(8), findsOneWidget);
      expect(
        tester.getTopLeft(row(8)).dy,
        lessThan(tester.getTopLeft(row(5)).dy),
      );
    });

    for (final (name, private, audience) in [
      ('a private account', true, StoryAudience.public),
      ('unknown privacy', null, StoryAudience.public),
      ('a followers story', false, StoryAudience.followers),
    ]) {
      testWidgets('no reshare toggle for $name', (tester) async {
        await show(tester, private: private, audience: audience);
        expect(current(tester).canAllowMentionReshare, isFalse);
        await tester.tap(find.byKey(const ValueKey('story-mention-tool')));
        await tester.pumpAndSettle();
        expect(row(5), findsOneWidget);
        expect(toggle(), findsNothing);
        expect(
          find.text('People you mention can reshare this story'),
          findsNothing,
        );
      });
    }

    testWidgets('a public account + public story can allow resharing', (
      tester,
    ) async {
      await show(tester);
      expect(current(tester).accountIsPublic, isTrue);
      expect(current(tester).sendsMentionReshare, isTrue);
      await tester.tap(find.byKey(const ValueKey('story-mention-tool')));
      await tester.pumpAndSettle();
      expect(toggle(), findsOneWidget);
    });

    testWidgets('reshare toggle sits right above Add and is stored', (
      tester,
    ) async {
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('story-mention-tool')));
      await tester.pumpAndSettle();
      expect(
        find.text('People you mention can reshare this story'),
        findsOneWidget,
      );
      final add = find.byKey(const ValueKey('story-mention-add'));
      expect(
        tester.getBottomLeft(toggle()).dy,
        lessThan(tester.getTopLeft(add).dy),
      );
      expect(
        tester.getTopLeft(add).dy - tester.getBottomLeft(toggle()).dy,
        lessThan(32),
      );
      expect(tester.widget<Switch>(toggle()).value, isTrue);
      await tester.tap(toggle());
      await tester.tap(row(5));
      await tester.pump();
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(current(tester).allowReshare, isFalse);
      // Reopening keeps the stored value.
      await tester.tap(find.byKey(const ValueKey('story-mention-tool')));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(toggle()).value, isFalse);
    });

    testWidgets('no more than 10 people can be checked', (tester) async {
      final search = FakeMentionsRepo()
        ..followed = [for (var i = 1; i <= 11; i++) user(i, 'user$i')];
      await show(tester, search: search);
      await tester.tap(find.byKey(const ValueKey('story-mention-tool')));
      await tester.pumpAndSettle();
      for (var i = 1; i <= 11; i++) {
        await tester.ensureVisible(row(i));
        await tester.tap(row(i));
        await tester.pump();
      }
      expect(find.text('You can mention up to 10 people.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('story-mention-add')));
      await tester.pumpAndSettle();
      expect(current(tester).mentions, hasLength(10));
      expect(current(tester).mentions.map((m) => m.id), isNot(contains(11)));
    });

    testWidgets('Aa text is a glass bubble with the @username in orange', (
      tester,
    ) async {
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('story-text-tool')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('story-text-input')),
        'Best coffee with my best friend @sarakhaled12',
      );
      await tester.tap(find.byKey(const ValueKey('story-text-done')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('story-text-bubble')), findsOneWidget);
      final text = tester.widget<RichText>(
        find.descendant(
          of: find.byKey(const ValueKey('story-text-bubble')),
          matching: find.byType(RichText),
        ),
      );
      final parts = (text.text as TextSpan).children!.cast<TextSpan>();
      expect(parts.first.style?.color, isNull); // inherits white
      expect((text.text as TextSpan).style!.color, Colors.white);
      expect(parts.last.text, '@sarakhaled12');
      expect(parts.last.style!.color, DarkColors.primaryColor);
    });

    test('text bubble: dark glass, rounded, never wider than 80%', () {
      const canvas = Size(390, 844);
      StoryTextGeometry geometry(String text) =>
          StoryTextGeometry(StoryTextLayer(id: 't', text: text), canvas);
      final short = geometry('Hi');
      expect(short.lines, 1);
      expect(short.radius, short.size.height / 2);
      final long = geometry('Best coffee with my best friend @sarakhaled12');
      expect(long.lines, greaterThan(1));
      expect(long.size.width, lessThanOrEqualTo(canvas.width * 0.8));
      expect(long.radius, lessThan(long.size.height / 2));
      expect(long.style.color, Colors.white);
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
