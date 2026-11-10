import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';
import 'package:travibe/features/stories/widgets/story_canvas.dart';

import 'fixtures.dart';

void main() {
  Future<void> show(
    WidgetTester tester,
    StoryExportController controller,
    StoryEditorDraft value,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 400,
            child: Stack(
              fit: StackFit.expand,
              children: [
                StoryCanvas(
                  draft: value,
                  exportController: controller,
                  onEditText: (_) {},
                  onTransform: (_, _, _) {},
                  onDelete: (_) {},
                ),
                // Simulate editor chrome covering the entire visible screen. It must
                // never enter the exported bitmap.
                const IgnorePointer(
                  child: ColoredBox(color: Color(0xFFFF00FF)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await precacheImage(
        MemoryImage(value.image.bytes),
        tester.element(find.byType(StoryCanvas)),
      );
    });
    await tester.pumpAndSettle();
  }

  Future<StoryExportImage> capture(
    WidgetTester tester,
    StoryExportController controller, {
    int edge = 400,
  }) async {
    final pending = controller.capture(longestEdge: edge);
    await tester.pump();
    return (await tester.runAsync(() => pending))!;
  }

  Future<Uint8List> pixels(WidgetTester tester, StoryExportImage result) async {
    return (await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(result.bytes);
      final frame = await codec.getNextFrame();
      try {
        final data = (await frame.image.toByteData())!;
        return Uint8List.fromList(data.buffer.asUint8List());
      } finally {
        frame.image.dispose();
        codec.dispose();
      }
    }))!;
  }

  testWidgets(
    'export retains the centered cover crop rather than letterboxing',
    (tester) async {
      final bytes = (await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawColor(Colors.red, BlendMode.src);
        canvas.drawRect(
          const Rect.fromLTWH(150, 0, 100, 100),
          Paint()..color = Colors.blue,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(400, 100);
        try {
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!;
          return Uint8List.fromList(data.buffer.asUint8List());
        } finally {
          image.dispose();
          picture.dispose();
        }
      }))!;
      final controller = StoryExportController();
      await show(
        tester,
        controller,
        StoryEditorDraft(
          image: StorySourceImage(
            path: '/local/crop.png',
            name: 'crop.png',
            width: 400,
            height: 100,
            bytes: bytes,
          ),
        ),
      );
      final rgba = await pixels(tester, await capture(tester, controller));
      for (final offset in [0, (200 * 200 + 100) * 4, (200 * 400 - 1) * 4]) {
        expect(rgba.sublist(offset, offset + 4), [33, 150, 243, 255]);
      }
    },
  );

  testWidgets('disposal while capture waits for paint rejects the result', (
    tester,
  ) async {
    final controller = StoryExportController();
    await show(tester, controller, draft());
    final pending = controller.capture();
    final rejection = expectLater(pending, throwsStateError);
    await tester.pumpWidget(const SizedBox.shrink());
    await rejection;
  });

  testWidgets('PNG preserves viewport dimensions and excludes editor chrome', (
    tester,
  ) async {
    final controller = StoryExportController();
    final value = draft();
    await show(tester, controller, value);
    final result = await capture(tester, controller);
    expect(result.width, 200);
    expect(result.height, 400);
    expect(result.contentType, 'image/png');
    expect(result.bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(result.draft, same(value));
    expect(() => result.bytes[0] = 0, throwsUnsupportedError);
    final rgba = await pixels(tester, result);
    // Fixture is opaque; exported content is not the magenta editor overlay.
    expect(rgba[3], 255);
    expect(rgba.take(4), isNot([255, 0, 255, 255]));
    final larger = await capture(tester, controller, edge: 800);
    expect([larger.width, larger.height], [400, 800]);
  });

  testWidgets('committed text positions and scales affect exported pixels', (
    tester,
  ) async {
    final controller = StoryExportController();
    final original = draft();
    await show(tester, controller, original);
    final bare = await pixels(tester, await capture(tester, controller));
    final text = StoryTextLayer(
      id: 'text',
      text: 'Trip',
      center: const Offset(.5, .3),
      scale: 1.5,
    );
    await show(tester, controller, original.withLayers([text]));
    final first = await pixels(tester, await capture(tester, controller));
    expect(first, isNot(orderedEquals(bare)));
    await show(
      tester,
      controller,
      original.withLayers([
        text.copyWith(center: const Offset(.5, .7), scale: 2),
      ]),
    );
    final moved = await pixels(tester, await capture(tester, controller));
    expect(moved, isNot(orderedEquals(first)));
    // Moving the text leaves the original top quarter untouched.
    expect(moved.take(200 * 100 * 4), orderedEquals(bare.take(200 * 100 * 4)));
  });

  testWidgets(
    'duplicate capture is rejected; controller detaches on disposal',
    (tester) async {
      final controller = StoryExportController();
      await show(tester, controller, draft());
      final first = controller.capture(longestEdge: 400);
      await expectLater(controller.capture(), throwsStateError);
      await tester.pump();
      await tester.runAsync(() => first);
      await tester.pumpWidget(const SizedBox.shrink());
      await expectLater(controller.capture(), throwsStateError);
    },
  );

  testWidgets('draft change during export rejects stale result; retry works', (
    tester,
  ) async {
    final controller = StoryExportController();
    final value = draft();
    await show(tester, controller, value);
    final pending = controller.capture(longestEdge: 400);
    final rejection = expectLater(pending, throwsStateError);
    await show(
      tester,
      controller,
      value.withLayers([StoryTextLayer(id: 'new', text: 'Updated')]),
    );
    await rejection;
    expect((await capture(tester, controller)).draft.layers, hasLength(1));
  });

  testWidgets('active drag cannot export the preview or delete target', (
    tester,
  ) async {
    final controller = StoryExportController();
    await show(
      tester,
      controller,
      draft().withLayers([StoryTextLayer(id: 'drag', text: 'Move me')]),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('story-layer-drag'))),
    );
    await gesture.moveBy(const Offset(20, 40));
    await tester.pump();
    expect(find.byKey(const ValueKey('story-delete-target')), findsOneWidget);
    await expectLater(controller.capture(), throwsStateError);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect((await capture(tester, controller)).height, 400);
  });

  testWidgets('invalid output dimensions and detached canvas are rejected', (
    tester,
  ) async {
    final controller = StoryExportController();
    await tester.pumpWidget(
      MaterialApp(
        home: StoryCanvas(
          draft: draft(),
          exportController: controller,
          onEditText: (_) {},
          onTransform: (_, _, _) {},
          onDelete: (_) {},
        ),
      ),
    );
    await expectLater(controller.capture(longestEdge: 0), throwsArgumentError);
    await tester.pumpWidget(const SizedBox.shrink());
    await expectLater(controller.capture(), throwsStateError);
  });

  testWidgets('invalid image is not exported as an error placeholder', (
    tester,
  ) async {
    final controller = StoryExportController();
    final invalid = StoryEditorDraft(
      image: StorySourceImage(
        path: '/bad.png',
        name: 'bad.png',
        width: 1,
        height: 1,
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: StoryCanvas(
          draft: invalid,
          exportController: controller,
          onEditText: (_) {},
          onTransform: (_, _, _) {},
          onDelete: (_) {},
        ),
      ),
    );
    await tester.runAsync(() async {
      // Let the codec reject the input without relying on fake-clock delays.
      try {
        await ui.instantiateImageCodec(invalid.image.bytes);
      } catch (_) {}
    });
    await tester.pumpAndSettle();
    expect(find.text('Unable to display this photo.'), findsOneWidget);
    await expectLater(controller.capture(), throwsStateError);
  });
}
