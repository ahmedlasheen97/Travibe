import 'dart:typed_data';
import 'dart:ui';
import 'package:travibe/core/media/image_content_type.dart';
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
  String? get contentType => sniffImageContentType(bytes);

  // Retain a local snapshot even if the picker's temporary file disappears.
  final Uint8List bytes;
}

/// Positions will be relative to the canvas, independently of device pixels.
abstract class StoryEditorLayer {
  const StoryEditorLayer({
    required this.id,
    this.center = const Offset(0.5, 0.5),
    this.scale = 1,
    this.rotation = 0,
  });

  final String id;
  final Offset center;
  final double scale;

  /// Radians, clockwise. Text layers keep 0.
  final double rotation;

  StoryEditorLayer transformed({
    required Offset center,
    required double scale,
    required double rotation,
  });
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

  @override
  StoryTextLayer transformed({
    required Offset center,
    required double scale,
    required double rotation,
  }) => copyWith(center: center, scale: scale);
}

/// Tapping a mention sticker cycles through these.
enum StoryMentionStyle {
  light,
  dark,
  brand,
  plain;

  StoryMentionStyle get next => values[(index + 1) % values.length];

  static StoryMentionStyle parse(Object? name) => values.firstWhere(
    (style) => style.name == name,
    orElse: () => StoryMentionStyle.light,
  );
}

class StoryMentionLayer extends StoryEditorLayer {
  const StoryMentionLayer({
    required super.id,
    required this.userId,
    required this.username,
    this.style = StoryMentionStyle.light,
    super.center,
    super.scale,
    super.rotation,
  });

  final int userId;
  final String username;
  final StoryMentionStyle style;

  String get text => '@$username';

  StoryMentionLayer copyWith({
    StoryMentionStyle? style,
    Offset? center,
    double? scale,
    double? rotation,
  }) => StoryMentionLayer(
    id: id,
    userId: userId,
    username: username,
    style: style ?? this.style,
    center: center ?? this.center,
    scale: scale ?? this.scale,
    rotation: rotation ?? this.rotation,
  );

  @override
  StoryMentionLayer transformed({
    required Offset center,
    required double scale,
    required double rotation,
  }) => copyWith(center: center, scale: scale, rotation: rotation);
}

/// Flattened into the uploaded photo; never sent as an element.
class StoryEmojiLayer extends StoryEditorLayer {
  const StoryEmojiLayer({
    required super.id,
    required this.emoji,
    super.center,
    super.scale,
    super.rotation,
  });

  final String emoji;

  @override
  StoryEmojiLayer transformed({
    required Offset center,
    required double scale,
    required double rotation,
  }) => StoryEmojiLayer(
    id: id,
    emoji: emoji,
    center: center,
    scale: scale,
    rotation: rotation,
  );
}

/// A freehand stroke. Points are normalized to the canvas (0–1); [width] is a
/// fraction of the canvas width so it survives any output resolution.
class StoryStroke {
  StoryStroke({
    required List<Offset> points,
    required this.colorArgb,
    required this.width,
  }) : points = List.unmodifiable(points);

  final List<Offset> points;
  final int colorArgb;
  final double width;
}

class StoryEditorDraft {
  StoryEditorDraft({
    required this.image,
    List<StoryEditorLayer> layers = const [],
    List<StoryStroke> strokes = const [],
    this.audience = StoryAudience.public,
  }) : layers = List.unmodifiable(layers),
       strokes = List.unmodifiable(strokes);

  final StorySourceImage image;
  final List<StoryEditorLayer> layers;
  final List<StoryStroke> strokes;
  final StoryAudience audience;

  /// Drawings and emojis are baked into the photo before upload.
  bool get hasFlattenedContent =>
      strokes.isNotEmpty || layers.any((layer) => layer is StoryEmojiLayer);

  StoryEditorDraft withLayers(List<StoryEditorLayer> layers) =>
      StoryEditorDraft(
        image: image,
        layers: layers,
        strokes: strokes,
        audience: audience,
      );

  StoryEditorDraft withStrokes(List<StoryStroke> strokes) => StoryEditorDraft(
    image: image,
    layers: layers,
    strokes: strokes,
    audience: audience,
  );

  StoryEditorDraft withAudience(StoryAudience audience) => StoryEditorDraft(
    image: image,
    layers: layers,
    strokes: strokes,
    audience: audience,
  );
}
