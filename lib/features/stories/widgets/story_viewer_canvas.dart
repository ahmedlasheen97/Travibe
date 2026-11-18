import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';
import 'package:travibe/features/stories/widgets/story_canvas.dart';

/// Read-only photo and v1 text/mention elements. Geometry, font, bounds, padding and cover crop
/// match StoryCanvas, without installing any editor gesture/delete controls.
class StoryViewerCanvas extends StatelessWidget {
  const StoryViewerCanvas({
    super.key,
    required this.image,
    required this.layers,
    required this.onReady,
    required this.onError,
  });
  final ImageProvider image;
  final List<StoryEditorLayer> layers;
  final VoidCallback onReady, onError;
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

  /// The mention sticker under [point] (canvas-local), topmost first.
  static StoryMentionLayer? mentionAt(
    List<StoryEditorLayer> layers,
    Offset point,
    Size size,
  ) {
    for (final layer in layers.reversed.whereType<StoryMentionLayer>()) {
      final geometry = StoryMentionGeometry(layer, size);
      final scale = geometry.fitScale(layer.scale);
      final center = geometry.bound(layer.center, scale, size);
      final rect = geometry.rect(center, scale, size);
      // Undo the sticker rotation around its center before testing.
      final local = point - rect.center;
      final cos = math.cos(-layer.rotation), sin = math.sin(-layer.rotation);
      final unrotated =
          rect.center +
          Offset(
            local.dx * cos - local.dy * sin,
            local.dx * sin + local.dy * cos,
          );
      if (rect.contains(unrotated)) return layer;
    }
    return null;
  }

  /// The mention (sticker or `@handle` inside text) under [point], topmost
  /// first, with its on-screen bounds for anchoring a popover.
  static StoryMentionHit? mentionHitAt(
    List<StoryEditorLayer> layers,
    Offset point,
    Size size,
  ) {
    for (final layer in layers.reversed) {
      if (layer is StoryMentionLayer) {
        if (mentionAt([layer], point, size) == null) continue;
        final geometry = StoryMentionGeometry(layer, size);
        final scale = geometry.fitScale(layer.scale);
        final center = geometry.bound(layer.center, scale, size);
        final rect = geometry.rect(center, scale, size);
        // Bounds of the rotated sticker.
        final cos = math.cos(layer.rotation).abs();
        final sin = math.sin(layer.rotation).abs();
        return StoryMentionHit(
          username: layer.username,
          rect: Rect.fromCenter(
            center: rect.center,
            width: rect.width * cos + rect.height * sin,
            height: rect.width * sin + rect.height * cos,
          ),
        );
      }
      if (layer is StoryTextLayer) {
        final geometry = StoryTextGeometry(layer, size);
        final scale = geometry.fitScale(layer.scale);
        final center = geometry.bound(layer.center, scale, size);
        final rect = geometry.rect(center, scale, size);
        if (!rect.contains(point)) continue;
        // Text layers never rotate; undo the scale around the center.
        final half = geometry.size.center(Offset.zero);
        final hit = geometry.mentionAt((point - rect.center) / scale + half);
        if (hit == null) continue;
        final (username, local) = hit;
        return StoryMentionHit(
          username: username,
          rect: Rect.fromPoints(
            rect.center + (local.topLeft - half) * scale,
            rect.center + (local.bottomRight - half) * scale,
          ),
        );
      }
    }
    return null;
  }

  Widget _layer(StoryEditorLayer layer, Size size) {
    final geometry = StoryLayerGeometry.of(layer, size);
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
  const StoryMentionHit({required this.username, required this.rect});
  final String username;
  final Rect rect;
}
