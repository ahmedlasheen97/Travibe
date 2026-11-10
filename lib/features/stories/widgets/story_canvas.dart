import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';

part 'story_canvas_export.dart';

/// Shared text geometry keeps hit testing, bounds and a future renderer aligned.
class StoryTextGeometry {
  StoryTextGeometry(StoryTextLayer layer, Size canvas) {
    style = TextStyle(
      fontFamily: 'Plus Jakarta Sans',
      fontSize: 24 * canvas.width / 390,
      fontWeight: FontWeight.w600,
      color: Colors.white,
      shadows: const [Shadow(color: Colors.black87, blurRadius: 3)],
    );
    final painter = TextPainter(
      text: TextSpan(text: layer.text, style: style),
      textDirection: TextDirection.ltr,
    );
    painter.layout(maxWidth: math.max(1, canvas.width * 0.8 - 16));
    size = painter.size + const Offset(16, 16);
    painter.dispose();
    maxScale = math.min(
      4,
      math.min(canvas.width / size.width, canvas.height / size.height),
    );
  }
  late final TextStyle style;
  late final Size size;
  late final double maxScale;

  double fitScale(double scale) =>
      scale.clamp(math.min(0.5, maxScale), maxScale);

  Offset bound(Offset center, double scale, Size canvas) {
    final halfWidth = math.min(0.5, size.width * scale / canvas.width / 2);
    final halfHeight = math.min(0.5, size.height * scale / canvas.height / 2);
    return Offset(
      center.dx.clamp(halfWidth, 1 - halfWidth),
      center.dy.clamp(halfHeight, 1 - halfHeight),
    );
  }
}

class StoryCanvas extends StatelessWidget {
  const StoryCanvas({
    super.key,
    required this.draft,
    required this.onEditText,
    required this.onTransform,
    required this.onDelete,
    this.exportController,
  });
  final StoryEditorDraft draft;
  final StoryExportController? exportController;
  final ValueChanged<StoryTextLayer> onEditText;
  final void Function(String id, Offset center, double scale) onTransform;
  final ValueChanged<String> onDelete;

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
  });
  final Size size;
  final StoryEditorDraft draft;
  final StoryExportController? exportController;
  final ValueChanged<StoryTextLayer> onEditText;
  final void Function(String id, Offset center, double scale) onTransform;
  final ValueChanged<String> onDelete;
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
    StoryTextLayer layer,
    StoryTextGeometry geometry,
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
    }
    setState(() {
      _activeId = layer.id;
      _startFocal = _local(details.focalPoint);
      _dropPoint = _startFocal;
      _startCenter = _center;
      _startScale = _scale;
      _baseGestureScale = 1;
      _pointerCount = details.pointerCount;
    });
  }

  void _update(
    String id,
    StoryTextGeometry geometry,
    ScaleUpdateDetails details,
  ) {
    if (!mounted || _cancelled || _activeId != id) return;
    final focal = _local(details.focalPoint);
    setState(() {
      if (details.pointerCount != _pointerCount) {
        _startFocal = focal;
        _startCenter = _center;
        _startScale = _scale;
        _baseGestureScale = details.scale > 0 ? details.scale : 1;
        _pointerCount = details.pointerCount;
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
    setState(() => _activeId = null);
    if (delete) {
      widget.onDelete(id);
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
                for (final layer
                    in widget.draft.layers.whereType<StoryTextLayer>())
                  _layer(layer),
              ],
            ),
          ),
        ),
      ),
      if (_activeId != null)
        Positioned.fromRect(
          rect: _deleteRect,
          child: IgnorePointer(
            child: Semantics(
              label: 'Drop here to delete text',
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

  Widget _layer(StoryTextLayer layer) {
    final geometry = StoryTextGeometry(layer, widget.size);
    final scale = _activeId == layer.id
        ? _scale
        : geometry.fitScale(layer.scale);
    final center = _activeId == layer.id
        ? _center
        : geometry.bound(layer.center, scale, widget.size);
    return Positioned(
      left: center.dx * widget.size.width - geometry.size.width / 2,
      top: center.dy * widget.size.height - geometry.size.height / 2,
      width: geometry.size.width,
      height: geometry.size.height,
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
            onTap: () => widget.onEditText(layer),
            onScaleStart: (details) => _start(layer, geometry, details),
            onScaleUpdate: (details) => _update(layer.id, geometry, details),
            onScaleEnd: (details) => _end(layer.id, details),
            child: Semantics(
              label: 'Edit text: ${layer.text}',
              button: true,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: RichText(
                  textDirection: TextDirection.ltr,
                  text: TextSpan(text: layer.text, style: geometry.style),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
