import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:travibe/core/widgets/top_glow_background.dart';

/// Background-only sample points (390-wide logical coordinates) in the Figma
/// Home reference: around the status-bar clock, behind "Hello, Salma", and
/// further out to check the falloff.
const samples = <(String, Offset)>[
  ('clock left', Offset(5, 24)),
  ('above clock', Offset(40, 8)),
  ('clock right', Offset(100, 24)),
  ('status middle', Offset(200, 20)),
  ('x 240', Offset(240, 40)),
  ('top right', Offset(380, 20)),
  ('Hello left', Offset(8, 80)),
  ('Hello, Salma right', Offset(160, 80)),
  ('Hello/subtitle gap', Offset(60, 92)),
  ('below greeting', Offset(60, 140)),
  ('left y 200', Offset(10, 200)),
  ('y 260', Offset(100, 260)),
  ('page', Offset(5, 600)),
];

/// Figma page color behind the glow.
const pageColor = Color(0xFF0A0A0A);

/// Max per-channel difference (0..255) from the Figma pixel.
const tolerance = 3;

void main() {
  testWidgets('glow matches the Figma Home reference colors', (tester) async {
    final reference = img.decodePng(
      File('docs/figma/home/home_glow_reference.png').readAsBytesSync(),
    )!;
    final k = reference.width / 390;

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: boundary,
          child: const TopGlowBackground(
            color: pageColor,
            child: SizedBox.expand(),
          ),
        ),
      ),
    );
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final pixels = await tester.runAsync(() async {
      final image = await render.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return (image.width, data!);
    });
    final (width, bytes) = pixels!;

    final table = StringBuffer(
      'point                 figma (x,y)      figma RGB      ours RGB       Δ\n',
    );
    final failures = <String>[];
    for (final (name, point) in samples) {
      final f = reference.getPixel(
        (point.dx * k).round(),
        (point.dy * k).round(),
      );
      final figma = [f.r.toInt(), f.g.toInt(), f.b.toInt()];
      final i = (point.dy.round() * width + point.dx.round()) * 4;
      final ours = [
        bytes.getUint8(i),
        bytes.getUint8(i + 1),
        bytes.getUint8(i + 2),
      ];
      final delta = [for (var c = 0; c < 3; c++) ours[c] - figma[c]];
      table.writeln(
        '${name.padRight(21)} '
        '${'(${point.dx.round()},${point.dy.round()})'.padRight(16)} '
        '${figma.join(',').padRight(14)} '
        '${ours.join(',').padRight(14)} '
        '${delta.join(',')}',
      );
      if (delta.any((d) => d.abs() > tolerance)) failures.add(name);
    }
    // ignore: avoid_print
    print(table);
    expect(failures, isEmpty, reason: 'Off by more than $tolerance:\n$table');
  });
}
