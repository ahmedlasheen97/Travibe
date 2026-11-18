import 'package:flutter/material.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';
import 'package:travibe/features/stories/widgets/story_canvas.dart';

/// Read-only photo and v1 text elements. Geometry, font, bounds, padding and cover crop
/// match StoryCanvas, without installing any editor gesture/delete controls.
class StoryViewerCanvas extends StatelessWidget {
  const StoryViewerCanvas({
    super.key,
    required this.image,
    required this.layers,
    required this.onReady,
    required this.onError,
    this.highlightMentions = true,
  });
  final ImageProvider image;
  final List<StoryEditorLayer> layers;
  final VoidCallback onReady, onError;

  /// Orange `@handle`s; off for a reshare (its mentions are plain text).
  final bool highlightMentions;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      return ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image(
              image: image,
              key: const ValueKey('story-viewer-photo'),
              fit: BoxFit.cover,
              frameBuilder: (context, child, frame, synchronous) {
                if (synchronous || frame != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (context.mounted) onReady();
                  });
                }
                return child;
              },
              errorBuilder: (context, _, _) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (context.mounted) onError();
                });
                return const SizedBox.shrink();
              },
            ),
            for (final layer in layers) _layer(layer, size),
          ],
        ),
      );
    },
  );

  /// The `@username` inside a text bubble under [point] (canvas-local),
  /// topmost first, with the handle's and the whole bubble's on-screen bounds
  /// so the View profile card can sit under the bubble, pointing at the name.
  static StoryMentionHit? mentionHitAt(
    List<StoryEditorLayer> layers,
    Offset point,
    Size size,
  ) {
    for (final layer in layers.reversed.whereType<StoryTextLayer>()) {
      final geometry = StoryTextGeometry(layer, size);
      final scale = geometry.fitScale(layer.scale);
      final center = geometry.bound(layer.center, scale, size);
      final bubble = geometry.rect(center, scale, size);
      if (!bubble.contains(point)) continue;
      // Text layers never rotate; undo the scale around the center.
      final half = geometry.size.center(Offset.zero);
      final hit = geometry.mentionAt((point - bubble.center) / scale + half);
      if (hit == null) continue;
      final (username, local) = hit;
      return StoryMentionHit(
        username: username,
        rect: Rect.fromPoints(
          bubble.center + (local.topLeft - half) * scale,
          bubble.center + (local.bottomRight - half) * scale,
        ),
        bubble: bubble,
      );
    }
    return null;
  }

  Widget _layer(StoryEditorLayer layer, Size size) {
    final geometry = StoryLayerGeometry.of(
      layer,
      size,
      highlightMentions: highlightMentions,
    );
    final scale = geometry.fitScale(layer.scale);
    final center = geometry.bound(layer.center, scale, size);
    return Positioned(
      key: ValueKey('story-viewer-layer-${layer.id}'),
      left: center.dx * size.width - geometry.size.width / 2,
      top: center.dy * size.height - geometry.size.height / 2,
      width: geometry.size.width,
      height: geometry.size.height,
      child: Transform.rotate(
        angle: layer.rotation,
        child: Transform.scale(scale: scale, child: geometry.content()),
      ),
    );
  }
}

/// A tapped mention: who, and where it is drawn (canvas-local).
class StoryMentionHit {
  const StoryMentionHit({
    required this.username,
    required this.rect,
    required this.bubble,
  });
  final String username;

  /// The `@username` itself.
  final Rect rect;

  /// The whole text bubble it is in.
  final Rect bubble;
}
