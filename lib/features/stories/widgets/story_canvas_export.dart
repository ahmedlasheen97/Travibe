part of 'story_canvas.dart';

/// PNG of the visible photo viewport and committed text, without editor chrome.
class StoryExportImage {
  StoryExportImage._(Uint8List bytes, this.width, this.height, this.draft)
    : bytes = bytes.asUnmodifiableView();

  final Uint8List bytes;
  final int width;
  final int height;
  final StoryEditorDraft draft;
  String get contentType => 'image/png';
  String get filename => 'story.png';
}

/// Scoped to one mounted canvas. Does not upload or publish anything.
class StoryExportController {
  _GestureCanvasState? _canvas;
  bool get isInteracting =>
      _canvas?._activeId != null || (_canvas?._pointers.isNotEmpty ?? false);

  void _attach(_GestureCanvasState canvas) {
    if (_canvas != null && _canvas != canvas) {
      throw StateError('A Story export controller must have only one canvas.');
    }
    _canvas = canvas;
  }

  void _detach(_GestureCanvasState canvas) {
    if (_canvas == canvas) _canvas = null;
  }

  /// Preserve the actual viewport aspect ratio/crop. 1920 is a bounded client
  /// export policy, not a claim about the still-unverified Story API limits.
  Future<StoryExportImage> capture({int longestEdge = 1920}) async {
    final canvas = _canvas;
    if (canvas == null || !canvas.mounted) {
      throw StateError('The Story canvas is unavailable.');
    }
    if (longestEdge < 64 || longestEdge > 1920) {
      throw ArgumentError.value(longestEdge, 'longestEdge', 'Must be 64–1920');
    }
    if (canvas._exporting ||
        canvas._activeId != null ||
        canvas._pointers.isNotEmpty ||
        !canvas._photoReady) {
      throw StateError('Wait for the photo and editing gesture to finish.');
    }
    final draft = canvas.widget.draft;
    final size = canvas.widget.size;
    final boundary = canvas._renderKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.hasSize) {
      throw StateError('The Story canvas has not rendered.');
    }
    canvas._exporting = true;
    ui.Image? image;
    try {
      // Always synchronize with paint, including release builds. The boundary
      // may otherwise still contain the previous Cubit state's rendered layer.
      await WidgetsBinding.instance.endOfFrame;
      if (_canvas != canvas ||
          !canvas.mounted ||
          !identical(canvas.widget.draft, draft) ||
          canvas.widget.size != size ||
          canvas._activeId != null ||
          canvas._pointers.isNotEmpty) {
        throw StateError('The Story changed during export. Please try again.');
      }
      // Capturing before the next paint would export an older draft.
      assert(() {
        if (boundary.debugNeedsPaint) {
          throw StateError('Wait for the Story canvas to paint.');
        }
        return true;
      }());
      image = await boundary.toImage(
        pixelRatio: longestEdge / math.max(size.width, size.height),
      );
      final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
      if (_canvas != canvas ||
          !canvas.mounted ||
          !identical(canvas.widget.draft, draft) ||
          canvas.widget.size != size ||
          canvas._activeId != null ||
          canvas._pointers.isNotEmpty) {
        throw StateError('The Story changed during export. Please try again.');
      }
      if (encoded == null) {
        throw StateError('Unable to encode the Story image.');
      }
      return StoryExportImage._(
        Uint8List.fromList(
          encoded.buffer.asUint8List(
            encoded.offsetInBytes,
            encoded.lengthInBytes,
          ),
        ),
        image.width,
        image.height,
        draft,
      );
    } finally {
      image?.dispose();
      canvas._exporting = false;
    }
  }
}
