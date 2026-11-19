import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/widgets/image_retry_signal.dart';
import 'package:travibe/core/widgets/post_card.dart';
import '../../helpers/fake_network_images.dart';

/// Fails while [fail] is true; otherwise decodes a 1×1 PNG.
class FlakyImage extends ImageProvider<FlakyImage> {
  bool fail = true;
  int loads = 0;

  @override
  Future<FlakyImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(FlakyImage key, ImageDecoderCallback decode) {
    loads++;
    return OneFrameImageStreamCompleter(_load(decode));
  }

  Future<ImageInfo> _load(ImageDecoderCallback decode) async {
    if (fail) throw Exception('offline');
    final buffer = await ui.ImmutableBuffer.fromUint8List(transparentPng);
    final codec = await decode(buffer);
    final frame = await codec.getNextFrame();
    return ImageInfo(image: frame.image);
  }
}

void main() {
  testWidgets('a failed post image keeps the placeholder and reloads when the '
      'retry signal fires', (tester) async {
    final image = FlakyImage();
    final signal = ImageRetrySignal();
    addTearDown(signal.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: RetryingPostImage(
          image: image,
          height: 100,
          signal: signal,
          errorBuilder: (_) => const Icon(
            Icons.broken_image_outlined,
            key: ValueKey('placeholder'),
          ),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.byKey(const ValueKey('placeholder')), findsOneWidget);
    expect(image.loads, 1);
    expect(signal.failedCount.value, 1);

    image.fail = false;
    await tester.runAsync(() async {
      signal.bump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(image.loads, 2);
    expect(find.byKey(const ValueKey('placeholder')), findsNothing);
    expect(signal.failedCount.value, 0);

    // A loaded image ignores later signals.
    signal.bump();
    await tester.pump();
    expect(image.loads, 2);
  });

  testWidgets('automatic retries stop after 5 failed attempts; a manual '
      'Refresh still retries', (tester) async {
    final image = FlakyImage(); // always fails
    final signal = ImageRetrySignal();
    addTearDown(signal.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: RetryingPostImage(
          image: image,
          height: 100,
          signal: signal,
          errorBuilder: (_) => const Icon(
            Icons.broken_image_outlined,
            key: ValueKey('placeholder'),
          ),
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    await settle();
    expect(image.loads, 1);
    expect(signal.failedCount.value, 1);

    // Four more automatic retries reach the cap of 5 failed attempts.
    for (var i = 2; i <= 5; i++) {
      signal.bump();
      await settle();
      expect(image.loads, i);
    }
    expect(find.byKey(const ValueKey('placeholder')), findsOneWidget);
    // Capped: no longer keeps the reconnect monitor running.
    expect(signal.failedCount.value, 0);

    signal.bump();
    await settle();
    expect(image.loads, 5);

    // Refresh / pull-to-refresh retries anyway and resets the cap.
    signal.bump(manual: true);
    await settle();
    expect(image.loads, 6);
    expect(signal.failedCount.value, 1);
    signal.bump();
    await settle();
    expect(image.loads, 7);
  });
}
