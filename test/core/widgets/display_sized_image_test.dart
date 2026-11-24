import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/widgets/display_sized_image.dart';
import 'package:travibe/core/widgets/post_card.dart';

import '../../helpers/fake_network_images.dart';
import '../../helpers/screen_util.dart';

Future<Uint8List> png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = Colors.orange,
  );
  final image = await recorder.endRecording().toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

void main() {
  group('targetSize (cover, never upscale)', () {
    test('landscape photo covers the box height', () {
      final size = DisplaySizedImage.targetSize(2048, 1024, 1050, 660);
      expect((size.width, size.height), (1320, 660));
    });

    test('portrait photo covers the box width', () {
      final size = DisplaySizedImage.targetSize(1536, 2048, 1050, 660);
      expect((size.width, size.height), (1050, 1400));
    });

    test('a photo already smaller than the box is decoded as is', () {
      final size = DisplaySizedImage.targetSize(300, 200, 1050, 660);
      expect((size.width, size.height), (null, null));
    });
  });

  testWidgets('decodes at the covering size, not full resolution', (
    tester,
  ) async {
    final bytes = (await tester.runAsync(() => png(400, 200)))!;
    final provider = DisplaySizedImage(
      MemoryImage(bytes),
      width: 100,
      height: 100,
    );
    final info = (await tester.runAsync(() async {
      final stream = provider.resolve(ImageConfiguration.empty);
      final completer = Completer<ImageInfo>();
      stream.addListener(
        ImageStreamListener((info, _) => completer.complete(info)),
      );
      return completer.future;
    }))!;
    expect((info.image.width, info.image.height), (200, 100));
    info.dispose();
  });

  test('each size is a separate cache entry from the original', () {
    const original = NetworkImage('https://example.invalid/a.jpg');
    const a = DisplaySizedImage(original, width: 100, height: 100);
    expect(a, const DisplaySizedImage(original, width: 100, height: 100));
    expect(
      a,
      isNot(const DisplaySizedImage(original, width: 200, height: 100)),
    );
    expect(a, isNot(original));
  });

  testWidgets('of() scales by device pixel ratio; unbounded boxes pass '
      'through', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 3),
        child: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    const original = NetworkImage('https://example.invalid/a.jpg');
    final sized =
        DisplaySizedImage.of(
              context,
              original,
              logicalWidth: 40,
              logicalHeight: 40.2,
            )
            as DisplaySizedImage;
    expect((sized.width, sized.height), (120, 121));
    expect(sized.imageProvider, same(original));
    expect(
      DisplaySizedImage.of(
        context,
        original,
        logicalWidth: double.infinity,
        logicalHeight: 40,
      ),
      same(original),
    );
  });

  testWidgets('PostCard decodes its photo, carousel and avatar at drawn size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await withFakeNetworkImages(() async {
      Future<void> show(PostCard card) => tester.pumpWidget(
        withScreenUtil(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(width: 360, child: card),
              ),
            ),
          ),
        ),
      );
      DisplaySizedImage sizedOf(ImageProvider? provider) =>
          provider! as DisplaySizedImage;

      await show(
        const PostCard(
          name: 'Sara',
          avatar: 'https://example.invalid/avatar.jpg',
          avatarSize: 40,
          time: 'now',
          text: '',
          image: 'https://example.invalid/photo.jpg',
          likes: '0',
          comments: '0',
        ),
      );
      await tester.pump();
      final photo = find.byWidgetPredicate(
        (w) => w is Image && w.image is DisplaySizedImage,
      );
      expect(photo, findsOneWidget);
      final drawn = tester.getSize(photo);
      final sized = sizedOf(tester.widget<Image>(photo).image);
      expect(
        (sized.width, sized.height),
        ((drawn.width * 3).ceil(), (drawn.height * 3).ceil()),
      );
      expect(
        (sized.imageProvider as NetworkImage).url,
        'https://example.invalid/photo.jpg',
      );
      final avatar = sizedOf(
        tester
            .widget<CircleAvatar>(
              find.byKey(const ValueKey('post-author-avatar')),
            )
            .foregroundImage,
      );
      expect((avatar.width, avatar.height), (120, 120));

      await show(
        const PostCard(
          name: 'Sara',
          avatar: null,
          time: 'now',
          text: '',
          images: [
            'https://example.invalid/1.jpg',
            'https://example.invalid/2.jpg',
          ],
          likes: '0',
          comments: '0',
        ),
      );
      await tester.pump();
      final page = find.byWidgetPredicate(
        (w) => w is Image && w.image is DisplaySizedImage,
      );
      final pageSize = tester.getSize(page.first);
      final pageImage = sizedOf(tester.widget<Image>(page.first).image);
      expect(
        (pageImage.width, pageImage.height),
        ((pageSize.width * 3).ceil(), (pageSize.height * 3).ceil()),
      );
    });
  });
}
