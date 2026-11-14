import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';
import 'package:travibe/features/stories/widgets/story_drawing.dart';
import 'package:travibe/features/stories/widgets/story_layer_geometry.dart';

export 'package:travibe/features/stories/widgets/story_layer_geometry.dart';

part 'story_canvas_export.dart';

typedef StoryLayerTransform =
    void Function(String id, Offset center, double scale, double rotation);

class StoryCanvas extends StatelessWidget {
  const StoryCanvas({
    super.key,
    required this.draft,
    required this.onEditText,
    required this.onTransform,
    required this.onDelete,
    this.exportController,
    this.onTransformLayer,
    this.onCycleMentionStyle,
    this.drawing = false,
    this.brushColor = Colors.white,
    this.brushWidth = 6,
    this.onStroke,
  });
  final StoryEditorDraft draft;
  final StoryExportController? exportController;
  final ValueChanged<StoryTextLayer> onEditText;
  final void Function(String id, Offset center, double scale) onTransform;

  /// Preferred over [onTransform] when set; includes sticker rotation.
  final StoryLayerTransform? onTransformLayer;
  final ValueChanged<String>? onCycleMentionStyle;
  final ValueChanged<String> onDelete;

  /// Drawing mode: finger input becomes strokes and stickers are inert.
  final bool drawing;
  final Color brushColor;
  final double brushWidth;
  final ValueChanged<StoryStroke>? onStroke;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      if (size.isEmpty) return const SizedBox.shrink();
      // A viewport change cancels any unfinished gesture rather than committing
      // coordinates calculated in an obsolete canvas. Committed state is retained.
      return _GestureCanvas(
        key: ValueKey(size),
        size: size,
        draft: draft,
        onEditText: onEditText,
        onTransform: onTransform,
        onDelete: onDelete,
        exportController: exportController,
        onTransformLayer: onTransformLayer,
        onCycleMentionStyle: onCycleMentionStyle,
        drawing: drawing,
        brushColor: brushColor,
        brushWidth: brushWidth,
        onStroke: onStroke,
      );
    },
  );
}

class _GestureCanvas extends StatefulWidget {
  const _GestureCanvas({
    super.key,
    required this.size,
    required this.draft,
    required this.onEditText,
    required this.onTransform,
    required this.onDelete,
    this.exportController,
    this.onTransformLayer,
    this.onCycleMentionStyle,
    this.drawing = false,
    this.brushColor = Colors.white,
    this.brushWidth = 6,
    this.onStroke,
  });
  final Size size;
  final StoryEditorDraft draft;
  final StoryExportController? exportController;
  final ValueChanged<StoryTextLayer> onEditText;
  final void Function(String id, Offset center, double scale) onTransform;
  final StoryLayerTransform? onTransformLayer;
  final ValueChanged<String>? onCycleMentionStyle;
  final ValueChanged<String> onDelete;
  final bool drawing;
  final Color brushColor;
  final double brushWidth;
  final ValueChanged<StoryStroke>? onStroke;
  @override
  State<_GestureCanvas> createState() => _GestureCanvasState();
}

class _GestureCanvasState extends State<_GestureCanvas> {
  final _canvasKey = GlobalKey();
  final _renderKey = GlobalKey();
  bool _photoReady = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    widget.exportController?._attach(this);
  }

  @override
  void didUpdateWidget(covariant _GestureCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.exportController != widget.exportController) {
      oldWidget.exportController?._detach(this);
      widget.exportController?._attach(this);
    }
    if (!identical(oldWidget.draft.image, widget.draft.image)) {
      _photoReady = false;
    }
  }

  String? _activeId;
  Offset _center = Offset.zero;
  double _scale = 1;
  double _rotation = 0;
  double _startRotation = 0;
  double _baseGestureRotation = 0;
  Offset _startFocal = Offset.zero;
  Offset _startCenter = Offset.zero;
  double _startScale = 1;
  double _baseGestureScale = 1;
  int _pointerCount = 0;
  Offset _dropPoint = Offset.zero;
  final _pointers = <int>{};
  bool _cancelled = false;

  @override
  void deactivate() {
    widget.exportController?._detach(this);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    widget.exportController?._attach(this);
  }

  @override
  void dispose() {
    widget.exportController?._detach(this);
    _activeId = null;
    _pointers.clear();
    super.dispose();
  }

  Offset _local(Offset global) =>
      (_canvasKey.currentContext!.findRenderObject() as RenderBox)
          .globalToLocal(global);

  Rect get _deleteRect {
    final bottom = MediaQuery.paddingOf(context).bottom + 16;
    return Rect.fromLTWH(
      (widget.size.width - 88) / 2,
      widget.size.height - bottom - 72,
      88,
      72,
    );
  }

  void _start(
    StoryEditorLayer layer,
    StoryLayerGeometry geometry,
    ScaleStartDetails details,
  ) {
    if (!mounted ||
        _cancelled ||
        (_activeId != null && _activeId != layer.id)) {
      return;
    }
    if (_activeId == null) {
      _scale = geometry.fitScale(layer.scale);
      _center = geometry.bound(layer.center, _scale, widget.size);
      _rotation = layer.rotation;
    }
    setState(() {
      _activeId = layer.id;
      _startFocal = _local(details.focalPoint);
      _dropPoint = _startFocal;
      _startCenter = _center;
      _startScale = _scale;
      _startRotation = _rotation;
      _baseGestureScale = 1;
      _baseGestureRotation = 0;
      _pointerCount = details.pointerCount;
    });
  }

  void _update(
    StoryEditorLayer layer,
    StoryLayerGeometry geometry,
    ScaleUpdateDetails details,
  ) {
    final id = layer.id;
    if (!mounted || _cancelled || _activeId != id) return;
    final focal = _local(details.focalPoint);
    setState(() {
      if (details.pointerCount != _pointerCount) {
        _startFocal = focal;
        _startCenter = _center;
        _startScale = _scale;
        _startRotation = _rotation;
        _baseGestureScale = details.scale > 0 ? details.scale : 1;
        _baseGestureRotation = details.rotation;
        _pointerCount = details.pointerCount;
      }
      // Text stays horizontal, as before; stickers follow the two-finger twist.
      if (layer is! StoryTextLayer) {
        _rotation = _startRotation + details.rotation - _baseGestureRotation;
      }
      _dropPoint = focal;
      _scale = geometry.fitScale(
        _startScale * details.scale / _baseGestureScale,
      );
      final delta = focal - _startFocal;
      _center = geometry.bound(
        _startCenter +
            Offset(delta.dx / widget.size.width, delta.dy / widget.size.height),
        _scale,
        widget.size,
      );
    });
  }

  void _cancel() {
    if (mounted && _activeId != null) setState(() => _activeId = null);
  }

  void _end(String layerId, ScaleEndDetails details) {
    if (!mounted ||
        _cancelled ||
        _activeId != layerId ||
        details.pointerCount != 0) {
      return;
    }
    _finish();
  }

  void _finish() {
    if (!mounted || _cancelled || _activeId == null) return;
    final id = _activeId!;
    final delete = _deleteRect.contains(_dropPoint);
    final center = _center;
    final scale = _scale;
    final rotation = _rotation;
    setState(() => _activeId = null);
    if (delete) {
      widget.onDelete(id);
    } else if (widget.onTransformLayer != null) {
      widget.onTransformLayer!(id, center, scale, rotation);
    } else {
      widget.onTransform(id, center, scale);
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    key: _canvasKey,
    fit: StackFit.expand,
    children: [
      // This subtree alone is renderable story content. Toolbar, delete target,
      // keyboard and text-entry UI are deliberately outside the boundary.
      KeyedSubtree(
        key: _renderKey,
        child: RepaintBoundary(
          key: const ValueKey('story-render-content'),
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  widget.draft.image.bytes,
                  key: const ValueKey('story-background'),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  frameBuilder: (context, child, frame, synchronous) {
                    _photoReady = synchronous || frame != null;
                    return child;
                  },
                  errorBuilder: (_, _, _) => const Center(
                    child: Text(
                      'Unable to display this photo.',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                if (widget.draft.strokes.isNotEmpty)
                  CustomPaint(
                    key: const ValueKey('story-strokes'),
                    painter: StoryStrokesPainter(widget.draft.strokes),
                  ),
                for (final layer in widget.draft.layers) _layer(layer),
              ],
            ),
          ),
        ),
      ),
      if (widget.drawing && widget.onStroke != null)
        Positioned.fill(
          child: StoryDrawingSurface(
            color: widget.brushColor,
            width: widget.brushWidth,
            onStroke: widget.onStroke!,
          ),
        ),
      if (_activeId != null)
        Positioned.fromRect(
          rect: _deleteRect,
          child: IgnorePointer(
            child: Semantics(
              label: 'Drop here to delete',
              child: Container(
                key: const ValueKey('story-delete-target'),
                decoration: BoxDecoration(
                  color: _deleteRect.contains(_dropPoint)
                      ? Colors.red
                      : Colors.black87,
                  borderRadius: BorderRadius.circular(36),
                  border: Border.all(color: Colors.white54),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.delete_outline, color: Colors.white),
                    Text(
                      'Delete',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );

  Widget _layer(StoryEditorLayer layer) {
    final geometry = StoryLayerGeometry.of(layer, widget.size);
    final active = _activeId == layer.id;
    final scale = active ? _scale : geometry.fitScale(layer.scale);
    final center = active
        ? _center
        : geometry.bound(layer.center, scale, widget.size);
    final rotation = active ? _rotation : layer.rotation;
    return Positioned(
      left: center.dx * widget.size.width - geometry.size.width / 2,
      top: center.dy * widget.size.height - geometry.size.height / 2,
      width: geometry.size.width,
      height: geometry.size.height,
      child: Transform.rotate(
        angle: rotation,
        child: Transform.scale(
          scale: scale,
          child: Listener(
            onPointerDown: (event) {
              if (_pointers.isEmpty) _cancelled = false;
              _pointers.add(event.pointer);
            },
            onPointerUp: (event) {
              if (!mounted) return;
              _pointers.remove(event.pointer);
              if (_pointers.isEmpty && _activeId == layer.id) {
                _dropPoint = _local(event.position);
                // ScaleRecognizer can end a segment when the first finger lifts,
                // then never start another segment before the last finger lifts.
                // Let normal onScaleEnd run first; finalize here only if needed.
                scheduleMicrotask(() {
                  if (_pointers.isEmpty) _finish();
                });
              }
            },
            onPointerCancel: (event) {
              if (!mounted) return;
              _pointers.remove(event.pointer);
              if (_activeId == layer.id) {
                _cancelled = true;
                _cancel();
              }
            },
            child: GestureDetector(
              key: ValueKey('story-layer-${layer.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: switch (layer) {
                StoryTextLayer() => () => widget.onEditText(layer),
                StoryMentionLayer() when widget.onCycleMentionStyle != null =>
                  () => widget.onCycleMentionStyle!(layer.id),
                _ => null,
              },
              onScaleStart: (details) => _start(layer, geometry, details),
              onScaleUpdate: (details) => _update(layer, geometry, details),
              onScaleEnd: (details) => _end(layer.id, details),
              child: Semantics(
                label: geometry.semanticLabel,
                button: true,
                child: geometry.content(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
