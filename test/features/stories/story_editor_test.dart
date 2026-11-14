import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/features/stories/cubit/story_editor_cubit.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';
import 'package:travibe/features/stories/screens/story_editor_screen.dart';
import 'package:travibe/features/stories/widgets/story_canvas.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'text IDs, edits and transforms preserve the source and other layers',
    () async {
      final original = draft();
      final cubit = StoryEditorCubit(original);
      addTearDown(cubit.close);
      cubit.saveText('First');
      final first = cubit.state.layers.single as StoryTextLayer;
      cubit.commitTransform(first.id, const Offset(0.3, 0.7), 1.8);
      cubit.saveText('Edited', id: first.id);
      cubit.saveText('Second');
      final edited = cubit.state.layers.first as StoryTextLayer;
      expect(edited.id, first.id);
      expect(edited.text, 'Edited');
      expect(edited.center, const Offset(0.3, 0.7));
      expect(edited.scale, 1.8);
      final secondId = cubit.state.layers.last.id;
      cubit.removeLayer(first.id);
      cubit.saveText('Third');
      expect(cubit.state.layers.map((layer) => layer.id).toSet().length, 2);
      expect(cubit.state.layers.first.id, secondId);
      expect(cubit.state.image, same(original.image));
      expect(cubit.state.image.bytes, photoBytes());
      expect(original.layers, isEmpty);
    },
  );

  test('blank creation and blank edit leave the draft intact', () async {
    final cubit = StoryEditorCubit(draft());
    addTearDown(cubit.close);
    cubit.saveText(' \n ');
    expect(cubit.state.layers, isEmpty);
    cubit.saveText('Keep this');
    final before = cubit.state;
    cubit.saveText('', id: before.layers.single.id);
    expect(cubit.state, same(before));
    cubit.commitTransform(
      before.layers.single.id,
      const Offset(double.nan, 1),
      1,
    );
    expect(cubit.state, same(before));
  });

  Future<void> show(WidgetTester tester, {StoryEditorDraft? initial}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.view.resetPadding);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => StoryEditorScreen(draft: initial ?? draft()),
                ),
              ),
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
  }

  StoryEditorDraft current(WidgetTester tester) =>
      tester.widget<StoryCanvas>(find.byType(StoryCanvas)).draft;
  StoryTextLayer textLayer(WidgetTester tester) =>
      current(tester).layers.single as StoryTextLayer;
  Finder overlay(WidgetTester tester) =>
      find.byKey(ValueKey('story-layer-${textLayer(tester).id}'));

  Future<void> add(WidgetTester tester, [String text = 'Trip memories']) async {
    await tester.tap(find.byKey(const ValueKey('story-text-tool')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('story-text-input')),
      text,
    );
    await tester.tap(find.byKey(const ValueKey('story-text-done')));
    await tester.pumpAndSettle();
  }

  Future<TestGesture> startDrag(WidgetTester tester) async {
    final gesture = await tester.startGesture(
      tester.getCenter(overlay(tester)),
    );
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    return gesture;
  }

  testWidgets('Aa autofocuses; Done adds text and tapping a layer edits it', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('story-text-tool')));
    await tester.pumpAndSettle();
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.enterText(find.byType(TextField), 'Hello Cairo');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    final first = textLayer(tester);
    await tester.tap(overlay(tester));
    await tester.pumpAndSettle();
    expect(find.text('Edit text'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Hello Cairo',
    );
    await tester.enterText(find.byType(TextField), 'Hello world');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(textLayer(tester).id, first.id);
    expect(textLayer(tester).text, 'Hello world');
    expect(textLayer(tester).center, first.center);
    expect(textLayer(tester).scale, first.scale);
  });

  testWidgets('empty Done and explicit Cancel never create or clear text', (
    tester,
  ) async {
    await show(tester);
    await add(tester, '  ');
    expect(current(tester).layers, isEmpty);
    await add(tester);
    final before = textLayer(tester);
    await tester.tap(overlay(tester));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(textLayer(tester), same(before));
    await tester.tap(overlay(tester));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Unsaved');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(textLayer(tester), same(before));
  });

  testWidgets(
    'drag previews locally and commits normalized coordinates only on release',
    (tester) async {
      await show(tester);
      await add(tester);
      final before = textLayer(tester);
      final start = tester.getCenter(overlay(tester));
      final gesture = await startDrag(tester);
      await gesture.moveBy(const Offset(70, 110));
      await tester.pump();
      expect(find.byKey(const ValueKey('story-delete-target')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('story-render-content')),
          matching: find.byKey(const ValueKey('story-delete-target')),
        ),
        findsNothing,
      );
      expect(textLayer(tester), same(before));
      expect(tester.getCenter(overlay(tester)), isNot(start));
      await gesture.up();
      await tester.pumpAndSettle();
      final after = textLayer(tester);
      expect(after.center.dx, greaterThan(before.center.dx));
      expect(after.center.dy, greaterThan(before.center.dy));
      expect(find.byKey(const ValueKey('story-delete-target')), findsNothing);
      final canvas = tester.getRect(find.byType(StoryCanvas));
      final center = tester.getCenter(overlay(tester));
      expect(
        center.dx,
        closeTo(canvas.left + canvas.width * after.center.dx, 0.01),
      );
      expect(
        center.dy,
        closeTo(canvas.top + canvas.height * after.center.dy, 0.01),
      );
    },
  );

  testWidgets(
    'dragging beyond either canvas corner keeps the whole text in bounds',
    (tester) async {
      await show(tester);
      await add(tester, 'Bounded');
      final canvas = tester.getRect(find.byType(StoryCanvas));
      for (final delta in [
        const Offset(-1500, -1500),
        const Offset(1500, 1500),
      ]) {
        final gesture = await startDrag(tester);
        await gesture.moveBy(delta);
        await gesture.up();
        await tester.pumpAndSettle();
        final rect = Rect.fromPoints(
          tester.getTopLeft(overlay(tester)),
          tester.getBottomRight(overlay(tester)),
        );
        expect(rect.left, greaterThanOrEqualTo(canvas.left - 0.01));
        expect(rect.top, greaterThanOrEqualTo(canvas.top - 0.01));
        expect(rect.right, lessThanOrEqualTo(canvas.right + 0.01));
        expect(rect.bottom, lessThanOrEqualTo(canvas.bottom + 0.01));
      }
    },
  );

  testWidgets(
    'pinch resizes, remains bounded, and commits when all fingers lift',
    (tester) async {
      await show(tester);
      await add(tester, 'Pinch');
      final center = tester.getCenter(overlay(tester));
      final left = await tester.startGesture(
        center - const Offset(20, 0),
        pointer: 1,
      );
      final right = await tester.startGesture(
        center + const Offset(20, 0),
        pointer: 2,
      );
      await left.moveTo(center - const Offset(45, 0));
      await right.moveTo(center + const Offset(45, 0));
      await tester.pump();
      expect(textLayer(tester).scale, 1);
      await left.up();
      await tester.pump();
      expect(textLayer(tester).scale, 1);
      await right.up();
      await tester.pumpAndSettle();
      expect(textLayer(tester).scale, greaterThan(1));
      expect(textLayer(tester).scale, lessThanOrEqualTo(4));
    },
  );

  testWidgets('only a drop inside the delete target removes the text', (
    tester,
  ) async {
    await show(tester);
    await add(tester);
    var gesture = await startDrag(tester);
    final target = tester.getRect(
      find.byKey(const ValueKey('story-delete-target')),
    );
    await gesture.moveTo(target.center);
    await tester.pump();
    expect(current(tester).layers, hasLength(1));
    await gesture.moveTo(target.topLeft - const Offset(2, 2));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(current(tester).layers, hasLength(1));
    gesture = await startDrag(tester);
    await gesture.moveTo(target.center);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(current(tester).layers, isEmpty);
  });

  testWidgets('cancelled drag restores the layer even over the delete target', (
    tester,
  ) async {
    await show(tester);
    await add(tester);
    final before = textLayer(tester);
    final gesture = await startDrag(tester);
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('story-delete-target'))),
    );
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(textLayer(tester), same(before));
    expect(find.byKey(const ValueKey('story-delete-target')), findsNothing);
  });

  testWidgets(
    'keyboard insets do not resize canvas; Back cancels text before exiting editor',
    (tester) async {
      await show(tester);
      final size = tester.getSize(find.byType(StoryCanvas));
      await tester.tap(find.byKey(const ValueKey('story-text-tool')));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(StoryCanvas)), size);
      await tester.enterText(find.byType(TextField), 'Not committed');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(StoryEditorScreen), findsOneWidget);
      expect(current(tester).layers, isEmpty);
      tester.view.resetViewInsets();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('story-back')));
      await tester.pumpAndSettle();
      expect(find.byType(StoryEditorScreen), findsNothing);
    },
  );

  testWidgets(
    'viewport resizing cancels an unfinished transform and retains normalized state',
    (tester) async {
      await show(tester);
      await add(tester);
      final before = textLayer(tester);
      final gesture = await startDrag(tester);
      await gesture.moveBy(const Offset(50, 30));
      await tester.pump();
      tester.view.physicalSize = const Size(600, 500);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(textLayer(tester), same(before));
      expect(find.byKey(const ValueKey('story-delete-target')), findsNothing);
      final canvas = tester.getRect(find.byType(StoryCanvas));
      expect(tester.getCenter(overlay(tester)), canvas.center);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancelled pinch restores scale after either pointer is cancelled',
    (tester) async {
      await show(tester);
      await add(tester, 'Pinch');
      final before = textLayer(tester);
      final center = tester.getCenter(overlay(tester));
      final left = await tester.startGesture(
        center - const Offset(20, 0),
        pointer: 1,
      );
      final right = await tester.startGesture(
        center + const Offset(20, 0),
        pointer: 2,
      );
      await left.moveTo(center - const Offset(45, 0));
      await right.moveTo(center + const Offset(45, 0));
      await tester.pump();
      await left.cancel();
      await right.moveBy(const Offset(15, 20));
      await right.up();
      await tester.pumpAndSettle();
      expect(textLayer(tester), same(before));
      expect(find.byKey(const ValueKey('story-delete-target')), findsNothing);
    },
  );

  testWidgets(
    'pinch can continue as a drag and commits once on final release',
    (tester) async {
      await show(tester);
      await add(tester, 'Pinch');
      final before = textLayer(tester);
      final center = tester.getCenter(overlay(tester));
      final left = await tester.startGesture(
        center - const Offset(20, 0),
        pointer: 1,
      );
      final right = await tester.startGesture(
        center + const Offset(20, 0),
        pointer: 2,
      );
      await left.moveTo(center - const Offset(45, 0));
      await right.moveTo(center + const Offset(45, 0));
      await left.up();
      await right.moveBy(const Offset(0, 30));
      await right.moveBy(const Offset(0, 50));
      await tester.pump();
      expect(textLayer(tester), same(before));
      await right.up();
      await tester.pumpAndSettle();
      expect(textLayer(tester).scale, greaterThan(1));
      expect(textLayer(tester).center.dy, greaterThan(before.center.dy));
    },
  );

  testWidgets(
    'long multiline text fits the canvas and delete target respects safe area',
    (tester) async {
      await show(tester);
      tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
      await tester.pump();
      await add(tester, List.filled(40, 'Travel memories').join('\n'));
      final canvas = tester.getRect(find.byType(StoryCanvas));
      final rect = Rect.fromPoints(
        tester.getTopLeft(overlay(tester)),
        tester.getBottomRight(overlay(tester)),
      );
      expect(rect.left, greaterThanOrEqualTo(canvas.left - 0.01));
      expect(rect.top, greaterThanOrEqualTo(canvas.top - 0.01));
      expect(rect.bottom, lessThanOrEqualTo(canvas.bottom + 0.01));
      final gesture = await startDrag(tester);
      final target = tester.getRect(
        find.byKey(const ValueKey('story-delete-target')),
      );
      expect(target.bottom, lessThanOrEqualTo(844 - 34));
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'text actions preserve image bytes, use no network, and keep controls outside content',
    (tester) async {
      var requests = 0;
      await HttpOverrides.runZoned(
        () async {
          final original = draft();
          await show(tester, initial: original);
          await add(tester);
          final gesture = await startDrag(tester);
          await gesture.moveBy(const Offset(30, 40));
          await gesture.up();
          await tester.pumpAndSettle();
          final before = textLayer(tester);
          await tester.tap(find.byKey(const ValueKey('story-draw-tool')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('story-draw-done')));
          await tester.pumpAndSettle();
          expect(textLayer(tester), same(before));
          expect(current(tester).image, same(original.image));
          expect(current(tester).image.bytes, photoBytes());
          expect(
            tester
                .widget<FilledButton>(find.byKey(const ValueKey('story-post')))
                .onPressed,
            isNull,
          );
          final content = find.byKey(const ValueKey('story-render-content'));
          expect(
            find.descendant(
              of: content,
              matching: find.byKey(const ValueKey('story-text-tool')),
            ),
            findsNothing,
          );
          expect(
            find.descendant(
              of: content,
              matching: find.byKey(const ValueKey('story-post')),
            ),
            findsNothing,
          );
          expect(
            find.descendant(
              of: content,
              matching: find.byKey(const ValueKey('story-delete-target')),
            ),
            findsNothing,
          );
        },
        createHttpClient: (_) {
          requests++;
          throw StateError('Network prohibited');
        },
      );
      expect(requests, 0);
    },
  );
}
