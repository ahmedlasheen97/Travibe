import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The supplied SVG uses an embedded PNG through `<pattern>`/`<use>`, unsupported
/// by the current SVG renderer. Render that original artwork using the exact
/// objectBoundingBox transform, without replacing or modifying the SVG asset.
class ChatEmptyIllustration extends StatelessWidget {
  const ChatEmptyIllustration({super.key});
  static const asset = 'assets/images/avatar/image 95.svg';
  static final _artwork = _load();
  static Future<void> warmUp() async {
    await _artwork;
  }

  static Future<void> precache(BuildContext context) async {
    final artwork = await _artwork;
    if (context.mounted) {
      await precacheImage(MemoryImage(artwork.bytes), context);
    }
  }

  static Future<
    ({Uint8List bytes, double width, double height, List<double> matrix})
  >
  _load() async {
    final svg = await rootBundle.loadString(asset);
    final data = RegExp(
      r'data:image/png;base64,([^"\s]+)',
    ).firstMatch(svg)?.group(1);
    final image = RegExp(r'<image\b[^>]+>').firstMatch(svg)?.group(0) ?? '';
    final width = double.tryParse(
      RegExp(r'width="([^"]+)"').firstMatch(image)?.group(1) ?? '',
    );
    final height = double.tryParse(
      RegExp(r'height="([^"]+)"').firstMatch(image)?.group(1) ?? '',
    );
    final matrix = RegExp(r'transform="matrix\(([^)]+)\)"')
        .firstMatch(svg)
        ?.group(1)
        ?.trim()
        .split(RegExp(r'[ ,]+'))
        .map(double.parse)
        .toList();
    if (data == null ||
        width == null ||
        height == null ||
        matrix == null ||
        matrix.length != 6 ||
        matrix[1] != 0 ||
        matrix[2] != 0 ||
        !matrix.every((n) => n.isFinite)) {
      throw const FormatException('Unsupported bundled illustration.');
    }
    return (
      bytes: base64Decode(data),
      width: width,
      height: height,
      matrix: matrix,
    );
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: 134,
      height: 121,
      child: FutureBuilder(
        future: _artwork,
        builder: (context, snapshot) {
          final art = snapshot.data;
          if (art == null) {
            return SvgPicture.asset(asset, width: 134, height: 121);
          }
          return ClipRect(
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  left: art.matrix[4] * 134,
                  top: art.matrix[5] * 121,
                  width: art.width * art.matrix[0] * 134,
                  height: art.height * art.matrix[3] * 121,
                  child: Image.memory(art.bytes, fit: BoxFit.fill),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
