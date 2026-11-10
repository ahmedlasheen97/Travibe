import 'package:flutter/material.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';
import 'package:travibe/features/stories/widgets/story_canvas.dart';

/// Read-only photo and v1 text. Geometry, font, bounds, padding and cover crop
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
  final List<StoryTextLayer> layers;
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
            for (final layer in layers) _text(layer, size),
          ],
        ),
      );
    },
  );
  Widget _text(StoryTextLayer layer, Size size) {
    final geometry = StoryTextGeometry(layer, size);
    final scale = geometry.fitScale(layer.scale);
    final center = geometry.bound(layer.center, scale, size);
    return Positioned(
      key: ValueKey('story-viewer-layer-${layer.id}'),
      left: center.dx * size.width - geometry.size.width / 2,
      top: center.dy * size.height - geometry.size.height / 2,
      width: geometry.size.width,
      height: geometry.size.height,
      child: Transform.scale(
        scale: scale,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: RichText(
            textDirection: TextDirection.ltr,
            text: TextSpan(text: layer.text, style: geometry.style),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
