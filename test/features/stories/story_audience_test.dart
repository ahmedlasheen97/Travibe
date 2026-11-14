import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/features/stories/cubit/story_editor_cubit.dart';
import 'package:travibe/features/stories/data/story_audience.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';
import 'package:travibe/features/stories/screens/story_editor_screen.dart';
import 'package:travibe/features/stories/widgets/story_canvas.dart';

import 'fixtures.dart';

void main() {
  Future<void> show(WidgetTester tester, {StoryEditorDraft? initial}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => StoryEditorScreen(draft: initial ?? draft()),
                ),
              ),
              child: const Text('Open story editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open story editor'));
    await tester.pumpAndSettle();
  }

  StoryEditorDraft current(WidgetTester tester) =>
      tester.widget<StoryCanvas>(find.byType(StoryCanvas)).draft;
  Finder getSheet() => find.byKey(const ValueKey('story-audience-sheet'));
  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('story-audience')));
    await tester.pumpAndSettle();
    expect(getSheet(), findsOneWidget);
  }

  Future<void> choose(WidgetTester tester, StoryAudience audience) async {
    await openSheet(tester);
    await tester.tap(
      find.byKey(ValueKey('story-audience-option-${audience.name}')),
    );
    await tester.pumpAndSettle();
    expect(getSheet(), findsNothing);
  }

  test(
    'Story choices are Public and Followers; new local drafts default to Public',
    () {
      expect(StoryAudience.values.map((value) => value.label), [
        'Public',
        'Followers',
      ]);
      expect(StoryAudience.values.map((value) => value.visibility), [
        'public',
        'followers',
      ]);
      expect(draft().audience, StoryAudience.public);
      expect(
        draft().withAudience(StoryAudience.followers).audience,
        StoryAudience.followers,
      );
    },
  );

  test(
    'audience switching preserves image bytes, layers, IDs and transforms',
    () async {
      final original = draft();
      final cubit = StoryEditorCubit(original);
      addTearDown(cubit.close);
      cubit.saveText('Keep this');
      final id = cubit.state.layers.single.id;
      cubit.commitTransform(id, const Offset(.3, .7), 1.8);
      final before = cubit.state.layers.single;
      cubit.setAudience(StoryAudience.followers);
      expect(cubit.state.layers.single, same(before));
      expect(cubit.state.image, same(original.image));
      expect(cubit.state.image.bytes, photoBytes());
      cubit.saveText('Edited', id: id);
      cubit.saveText('Another layer');
      cubit.commitTransform(id, const Offset(.4, .6), 2);
      expect(cubit.state.audience, StoryAudience.followers);
      final text = cubit.state.layers.first as StoryTextLayer;
      expect(text.id, id);
      expect(text.text, 'Edited');
      expect(text.center, const Offset(.4, .6));
      expect(text.scale, 2);
      cubit.removeLayer(id);
      expect(cubit.state.audience, StoryAudience.followers);
      cubit.setAudience(StoryAudience.public);
      expect(cubit.state.layers.single.id, isNot(id));
      expect(original.audience, StoryAudience.public);
      expect(original.layers, isEmpty);
    },
  );

  test(
    'same selection and disposed audience changes leave state untouched',
    () async {
      final cubit = StoryEditorCubit(draft());
      final original = cubit.state;
      cubit.setAudience(StoryAudience.public);
      expect(cubit.state, same(original));
      await cubit.close();
      cubit.setAudience(StoryAudience.followers);
      expect(cubit.state, same(original));
    },
  );

  testWidgets(
    'active audience pill offers exactly Public and Followers and switches immediately',
    (tester) async {
      await show(tester);
      expect(current(tester).audience, StoryAudience.public);
      await openSheet(tester);
      expect(find.byType(ListTile), findsNWidgets(2));
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      expect(find.text('Followers'), findsOneWidget);
      expect(find.text('Anyone can see your story.'), findsOneWidget);
      expect(
        find.text('Only people who follow you can see your story.'),
        findsOneWidget,
      );
      final publicOption = tester.widget<ListTile>(
        find.byKey(const ValueKey('story-audience-option-public')),
      );
      final followersOption = tester.widget<ListTile>(
        find.byKey(const ValueKey('story-audience-option-followers')),
      );
      expect((publicOption.leading as Icon).icon, Icons.language);
      expect((followersOption.leading as Icon).icon, Icons.people_outline);
      expect(find.text('Private'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('story-audience-option-followers')),
      );
      await tester.pumpAndSettle();
      expect(current(tester).audience, StoryAudience.followers);
      expect(getSheet(), findsNothing);
      expect(find.text('Followers'), findsOneWidget);
      await openSheet(tester);
      final selected = tester.widget<ListTile>(
        find.byKey(const ValueKey('story-audience-option-followers')),
      );
      expect((selected.trailing as Icon).icon, Icons.radio_button_checked);
      await tester.tap(
        find.byKey(const ValueKey('story-audience-option-public')),
      );
      await tester.pumpAndSettle();
      expect(current(tester).audience, StoryAudience.public);
      expect(find.text('Public'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dismissal and system Back close only the sheet and retain audience and draft',
    (tester) async {
      await show(
        tester,
        initial: draft().withAudience(StoryAudience.followers),
      );
      final before = current(tester);
      await openSheet(tester);
      await tester.tapAt(const Offset(10, 160));
      await tester.pumpAndSettle();
      expect(getSheet(), findsNothing);
      expect(current(tester), same(before));
      await openSheet(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(getSheet(), findsNothing);
      expect(find.byType(StoryEditorScreen), findsOneWidget);
      expect(current(tester), same(before));
      await tester.tap(find.byKey(const ValueKey('story-back')));
      await tester.pumpAndSettle();
      expect(find.byType(StoryEditorScreen), findsNothing);
      expect(find.text('Open story editor'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Followers survives text creation, dragging, editing and draw mode',
    (tester) async {
      await show(tester);
      await choose(tester, StoryAudience.followers);
      final image = current(tester).image;
      await tester.tap(find.byKey(const ValueKey('story-text-tool')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('story-text-input')),
        'Keep audience',
      );
      await tester.tap(find.byKey(const ValueKey('story-text-done')));
      await tester.pumpAndSettle();
      final id = current(tester).layers.single.id;
      final layer = find.byKey(ValueKey('story-layer-$id'));
      await tester.drag(layer, const Offset(32, 20));
      await tester.pumpAndSettle();
      expect(current(tester).audience, StoryAudience.followers);
      final transformed = current(tester).layers.single as StoryTextLayer;
      expect(transformed.center, isNot(const Offset(.5, .5)));
      await tester.tap(layer);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('story-text-input')),
        'Still Followers',
      );
      await tester.tap(find.byKey(const ValueKey('story-text-done')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('story-draw-tool')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('story-draw-done')));
      await tester.pumpAndSettle();
      expect(current(tester).audience, StoryAudience.followers);
      expect(current(tester).image, same(image));
      final edited = current(tester).layers.single as StoryTextLayer;
      expect(edited.id, id);
      expect(edited.text, 'Still Followers');
      expect(edited.center, transformed.center);
      expect(edited.scale, transformed.scale);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'duplicate audience openings and contending Text taps create one sheet',
    (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('story-audience')));
      await tester.tap(
        find.byKey(const ValueKey('story-audience')),
        warnIfMissed: false,
      );
      await tester.tap(
        find.byKey(const ValueKey('story-text-tool')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(getSheet(), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(current(tester).layers, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'audience selection never publishes or uploads and disabled Post retains draft',
    (tester) async {
      var requests = 0;
      await HttpOverrides.runZoned(
        () async {
          await show(tester);
          for (final audience in [
            StoryAudience.followers,
            StoryAudience.public,
          ]) {
            await choose(tester, audience);
            final before = current(tester);
            expect(
              tester
                  .widget<FilledButton>(
                    find.byKey(const ValueKey('story-post')),
                  )
                  .onPressed,
              isNull,
            );
            await tester.tap(find.byKey(const ValueKey('story-post')));
            await tester.pumpAndSettle();
            expect(current(tester), same(before));
            expect(current(tester).audience, audience);
          }
          expect(tester.takeException(), isNull);
        },
        createHttpClient: (_) {
          requests++;
          throw StateError('No Story network operations allowed');
        },
      );
      expect(requests, 0);
    },
  );
}
