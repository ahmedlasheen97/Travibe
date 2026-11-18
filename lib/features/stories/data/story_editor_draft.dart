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

/// Someone mentioned with the @ tool. Nothing is drawn on the story; the
/// API still reads them as mentions and notifies them.
class StoryMentionedUser {
  const StoryMentionedUser({required this.id, required this.username});
  final int id;
  final String username;
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
    List<StoryMentionedUser> mentions = const [],
    this.allowReshare = true,
    this.accountIsPublic = false,
  }) : layers = List.unmodifiable(layers),
       strokes = List.unmodifiable(strokes),
       mentions = List.unmodifiable(mentions);

  final StorySourceImage image;
  final List<StoryEditorLayer> layers;
  final List<StoryStroke> strokes;
  final StoryAudience audience;

  /// People picked with the @ tool (hidden mentions).
  final List<StoryMentionedUser> mentions;

  /// "People you mention can reshare this story" (the user's choice).
  final bool allowReshare;

  /// The author's account is known to be public. Captured from the current
  /// profile when the story is posted; false when unknown.
  final bool accountIsPublic;

  /// The API only accepts `allow_mention_reshare: true` for a public story by
  /// a public account (otherwise 422), so the toggle shows only then.
  bool get canAllowMentionReshare =>
      accountIsPublic && audience == StoryAudience.public;

  /// Whether `allow_mention_reshare: true` is sent.
  bool get sendsMentionReshare => allowReshare && canAllowMentionReshare;

  /// Drawings and emojis are baked into the photo before upload.
  bool get hasFlattenedContent =>
      strokes.isNotEmpty || layers.any((layer) => layer is StoryEmojiLayer);

  StoryEditorDraft _copy({
    List<StoryEditorLayer>? layers,
    List<StoryStroke>? strokes,
    StoryAudience? audience,
    List<StoryMentionedUser>? mentions,
    bool? allowReshare,
    bool? accountIsPublic,
  }) => StoryEditorDraft(
    image: image,
    layers: layers ?? this.layers,
    strokes: strokes ?? this.strokes,
    audience: audience ?? this.audience,
    mentions: mentions ?? this.mentions,
    allowReshare: allowReshare ?? this.allowReshare,
    accountIsPublic: accountIsPublic ?? this.accountIsPublic,
  );

  StoryEditorDraft withLayers(List<StoryEditorLayer> layers) =>
      _copy(layers: layers);

  StoryEditorDraft withStrokes(List<StoryStroke> strokes) =>
      _copy(strokes: strokes);

  StoryEditorDraft withAudience(StoryAudience audience) =>
      _copy(audience: audience);

  StoryEditorDraft withMentions(List<StoryMentionedUser> mentions) =>
      _copy(mentions: mentions);

  StoryEditorDraft withAllowReshare(bool allowReshare) =>
      _copy(allowReshare: allowReshare);

  StoryEditorDraft withAccountIsPublic(bool accountIsPublic) =>
      _copy(accountIsPublic: accountIsPublic);
}
