import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every SVG under assets/ must be bundled, parse with flutter_svg and draw
/// visible pixels. flutter_svg fails silently on some Figma exports (e.g. a
/// PNG wrapped in a `<pattern>` fill renders as nothing), so widget tests that
/// only find an SvgPicture can't catch it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final files =
      Directory('assets')
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path.replaceAll(r'\', '/'))
          .where((p) => p.toLowerCase().endsWith('.svg'))
          .toList()
        ..sort();

  test('assets/ contains SVGs to check', () => expect(files, isNotEmpty));

  for (final path in files) {
    test(path, () async {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      expect(
        manifest.listAssets(),
        contains(path),
        reason: '$path is not bundled (check pubspec.yaml assets)',
      );

      final source = await rootBundle.loadString(path);
      for (final (tag, why) in [
        ('<foreignObject', 'flutter_svg ignores <foreignObject>'),
        ('<pattern', 'flutter_svg draws image <pattern> fills as nothing'),
      ]) {
        if (tag == '<pattern' && !source.contains('<image')) continue;
        expect(
          source.contains(tag),
          isFalse,
          reason: '$path: $why — export it as PNG or flatten it',
        );
      }

      final info = await vg.loadPicture(SvgAssetLoader(path), null);
      addTearDown(info.picture.dispose);
      final w = info.size.width.ceil().clamp(1, 512);
      final h = info.size.height.ceil().clamp(1, 512);
      expect(info.size.isEmpty, isFalse, reason: '$path has no size');
      final image = await info.picture.toImage(w, h);
      addTearDown(image.dispose);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final pixels = bytes!.buffer.asUint8List();
      var visible = false;
      for (var i = 3; i < pixels.length; i += 4) {
        if (pixels[i] != 0) {
          visible = true;
          break;
        }
      }
      expect(visible, isTrue, reason: '$path renders no visible pixels');
    });
  }
}
