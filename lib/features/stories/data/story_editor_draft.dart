import 'dart:typed_data';
import 'dart:ui';
import 'package:travibe/features/stories/data/story_audience.dart';

/// Local editing data only. This is deliberately not an API request model.
class StorySourceImage {
  StorySourceImage({
    required this.path,
    required this.name,
    required this.width,
    required this.height,
    required Uint8List bytes,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView();

  final String path;
  final String name;
  final int width;
  final int height;

  /// Detect the original upload MIME from bytes, never from the filename.
  String? get contentType {
    bool starts(List<int> signature) =>
        bytes.length >= signature.length &&
        List.generate(
          signature.length,
          (i) => bytes[i] == signature[i],
        ).every((v) => v);
    if (starts([137, 80, 78, 71, 13, 10, 26, 10])) return 'image/png';
    if (starts([255, 216, 255])) return 'image/jpeg';
    if (starts([71, 73, 70, 56, 55, 97]) || starts([71, 73, 70, 56, 57, 97])) {
      return 'image/gif';
    }
    if (starts([82, 73, 70, 70]) &&
        bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return 'image/webp';
    }
    return null;
  }

  // Retain a local snapshot even if the picker's temporary file disappears.
  final Uint8List bytes;
}

/// Positions will be relative to the canvas, independently of device pixels.
abstract class StoryEditorLayer {
  const StoryEditorLayer({
    required this.id,
    this.center = const Offset(0.5, 0.5),
    this.scale = 1,
  });

  final String id;
  final Offset center;
  final double scale;
}

class StoryTextLayer extends StoryEditorLayer {
  const StoryTextLayer({
    required super.id,
    required this.text,
    super.center,
    super.scale,
  });

  final String text;

  StoryTextLayer copyWith({String? text, Offset? center, double? scale}) =>
      StoryTextLayer(
        id: id,
        text: text ?? this.text,
        center: center ?? this.center,
        scale: scale ?? this.scale,
      );
}

class StoryEditorDraft {
  StoryEditorDraft({
    required this.image,
    List<StoryEditorLayer> layers = const [],
    this.audience = StoryAudience.public,
  }) : layers = List.unmodifiable(layers);

  final StorySourceImage image;
  final List<StoryEditorLayer> layers;
  final StoryAudience audience;

  StoryEditorDraft withLayers(List<StoryEditorLayer> layers) =>
      StoryEditorDraft(image: image, layers: layers, audience: audience);

  StoryEditorDraft withAudience(StoryAudience audience) =>
      StoryEditorDraft(image: image, layers: layers, audience: audience);
}
