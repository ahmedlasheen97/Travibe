import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:travibe/features/stories/data/story_editor_draft.dart';
import 'package:travibe/features/stories/widgets/story_drawing.dart';
import 'package:travibe/features/stories/widgets/story_layer_geometry.dart';

/// The photo that is uploaded for a Story.
class StoryExportedImage {
  StoryExportedImage(
    Uint8List bytes,
    this.width,
    this.height, {
    required this.flattened,
  }) : bytes = bytes.asUnmodifiableView();
  final Uint8List bytes;
  final int width, height;

  /// True when drawings or emojis were baked in.
  final bool flattened;
  String get contentType => 'image/jpeg';
  String get filename => 'story.jpg';
}

typedef StoryJpegEncoder =
    Future<Uint8List> Function(
      Uint8List rgba,
      int width,
      int height,
      int quality,
    );

/// Exports what the editor showed as a Story-sized JPEG.
///
/// - Crops to the editor viewport (the same `BoxFit.cover` crop the user saw)
///   and fits it within [maxWidth]×[maxHeight]; never upscales.
/// - Draws strokes and emoji stickers only when present. Text and mentions are
///   never drawn: they stay API elements.
/// - The engine decodes the photo already downsampled (off the UI thread),
///   the raster thread renders, and JPEG encoding runs in a background isolate.
/// - Keeps the file under [maxBytes]: detailed photos step the quality down
///   ([quality] → [minQuality]), then shrink the frame, never below half size.
class StoryImageExporter {
  const StoryImageExporter({
    this.maxWidth = 1080,
    this.maxHeight = 1920,
    this.quality = 85,
    this.minQuality = 65,
    this.maxBytes = defaultMaxBytes,
    this.encoder,
  });

  /// "Under ~1 MB" with headroom.
  static const defaultMaxBytes = 950 * 1024;

  final int maxWidth, maxHeight, quality, minQuality, maxBytes;

  /// Override for tests; defaults to a `compute()` isolate.
  final StoryJpegEncoder? encoder;

  Future<StoryExportedImage> export(
    StoryEditorDraft draft,
    Size? viewport,
  ) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(draft.image.bytes);
    late Size view;
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (intrinsicWidth, intrinsicHeight) {
        view = _validViewport(viewport, intrinsicWidth, intrinsicHeight);
        // EXIF orientation may swap the axes after decoding. A uniform scale
        // is orientation-independent; take the larger of both so the visible
        // crop always has enough pixels.
        final scale = math.max(
          _fit(view, intrinsicWidth, intrinsicHeight),
          _fit(view, intrinsicHeight, intrinsicWidth),
        );
        return ui.TargetImageSize(
          width: math.max(1, (intrinsicWidth * scale).ceil()),
          height: math.max(1, (intrinsicHeight * scale).ceil()),
        );
      },
    );
    ui.Image? photo;
    try {
      photo = (await codec.getNextFrame()).image;
      final crop = _cropOf(view, photo.width, photo.height);
      final fit = math.min(
        1.0,
        math.min(maxWidth / crop.width, maxHeight / crop.height),
      );
      final width = math.max(1, math.min(maxWidth, (crop.width * fit).round()));
      final height = math.max(
        1,
        math.min(maxHeight, (crop.height * fit).round()),
      );
      final flattened = draft.hasFlattenedContent;
      final encode = encoder ?? _encodeInIsolate;
      final qualities = {
        quality,
        if (quality > 75) 75,
        minQuality,
      }.where((q) => q <= quality && q >= minQuality).toList();
      var w = width, h = height;
      while (true) {
        final pixels = await _render(photo, crop, view, draft, w, h);
        Uint8List? jpeg;
        for (final q in qualities) {
          jpeg = await encode(pixels, w, h, q);
          if (jpeg.length <= maxBytes) {
            return StoryExportedImage(jpeg, w, h, flattened: flattened);
          }
        }
        // Still too large at the lowest quality: shrink, but keep at least
        // half the story size so text and faces stay readable.
        final nextW = (w * .8).round(), nextH = (h * .8).round();
        if (nextW < width / 2 || nextH < height / 2) {
          return StoryExportedImage(jpeg!, w, h, flattened: flattened);
        }
        w = math.max(1, nextW);
        h = math.max(1, nextH);
      }
    } finally {
      photo?.dispose();
      codec.dispose();
    }
  }

  /// Renders the visible crop (and any drawings/emojis) at [width]×[height].
  Future<Uint8List> _render(
    ui.Image photo,
    Rect crop,
    Size view,
    StoryEditorDraft draft,
    int width,
    int height,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final bounds = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    canvas.drawImageRect(
      photo,
      crop,
      bounds,
      Paint()..filterQuality = FilterQuality.high,
    );
    if (draft.hasFlattenedContent) {
      // The output is exactly the viewport, so overlays use editor geometry.
      canvas
        ..clipRect(bounds)
        ..scale(width / view.width, height / view.height)
        ..clipRect(Offset.zero & view);
      paintStoryStrokes(canvas, view, draft.strokes);
      for (final layer in draft.layers.whereType<StoryEmojiLayer>()) {
        _paintEmoji(canvas, layer, view);
      }
    }
    final picture = recorder.endRecording();
    ui.Image? output;
    try {
      output = await picture.toImage(width, height);
      final rgba = await output.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (rgba == null) throw StateError('Unable to read the Story image.');
      return rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes);
    } finally {
      picture.dispose();
      output?.dispose();
    }
  }

  static Size _validViewport(Size? viewport, int width, int height) =>
      viewport == null || viewport.isEmpty || !viewport.isFinite
      ? Size(width.toDouble(), height.toDouble())
      : viewport;

  /// The source rectangle `BoxFit.cover` shows in [view].
  static Rect _cropOf(Size view, int width, int height) {
    final cover = math.max(view.width / width, view.height / height);
    return Rect.fromCenter(
      center: Offset(width / 2, height / 2),
      width: math.min(width.toDouble(), view.width / cover),
      height: math.min(height.toDouble(), view.height / cover),
    );
  }

  /// Decode scale so the visible crop just covers the output limit.
  double _fit(Size view, int width, int height) {
    final crop = _cropOf(view, width, height);
    return math.min(
      1.0,
      math.min(maxWidth / crop.width, maxHeight / crop.height),
    );
  }

  void _paintEmoji(Canvas canvas, StoryEmojiLayer layer, Size viewport) {
    final geometry = StoryEmojiGeometry(layer, viewport);
    final scale = geometry.fitScale(layer.scale);
    final center = geometry.bound(layer.center, scale, viewport);
    final painter = StoryEmojiGeometry.textPainter(layer.emoji, geometry.style);
    canvas
      ..save()
      ..translate(center.dx * viewport.width, center.dy * viewport.height)
      ..rotate(layer.rotation)
      ..scale(scale);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
    painter.dispose();
  }

  static Future<Uint8List> _encodeInIsolate(
    Uint8List rgba,
    int width,
    int height,
    int quality,
  ) => compute(
    encodeStoryJpeg,
    StoryJpegJob(rgba, width, height, quality),
    debugLabel: 'story-jpeg',
  );
}

class StoryJpegJob {
  const StoryJpegJob(this.rgba, this.width, this.height, this.quality);
  final Uint8List rgba;
  final int width, height, quality;
}

/// Top-level so it can run in a background isolate.
Uint8List encodeStoryJpeg(StoryJpegJob job) => img.encodeJpg(
  img.Image.fromBytes(
    width: job.width,
    height: job.height,
    bytes: job.rgba.buffer,
    bytesOffset: job.rgba.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  ),
  quality: job.quality,
);
