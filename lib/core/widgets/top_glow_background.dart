import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:travibe/core/constants/app_sizes.dart';

/// Figma "bg blur circle": a soft orange glow at the top-left of the main
/// tabs (Home, Explore, Buddies, Profile).
///
/// Paints behind [child], fixed at the very top of the screen (under the
/// status bar); scrolling content passes over it. The blur is rasterized once
/// into a cached image on its own layer, so scrolling never repaints it.
///
/// Opaque bars inside [child] (e.g. a pinned tab bar) use [TopGlowBackdrop]
/// so they show the same page color and glow instead of cutting across it.
class TopGlowBackground extends StatefulWidget {
  const TopGlowBackground({super.key, required this.child, this.color});

  final Widget child;

  /// Optional page background painted under the glow (screens that own a
  /// Scaffold pass its color and make the Scaffold transparent). Without it
  /// the theme's scaffold color is assumed for [TopGlowBackdrop].
  final Color? color;

  /// Figma token "Color/Alpha/bg blur circle" (#E45C10 at 84%).
  static const glowColor = Color(0xD6E45C10);

  /// Figma layer blur.
  static const figmaLayerBlur = 150.0;

  /// Gaussian σ per unit of Figma blur, fitted to the Figma render
  /// (docs/figma/home_toasts/post_published.png on #0A0A0A: ≈17% orange at
  /// the clock, ≈8% at x 240, ≈6% at (5, 200) → σ ≈ 135 at 390 wide).
  static const blurToSigma = 0.9;

  static const glowKey = ValueKey('top-glow');

  @override
  State<TopGlowBackground> createState() => _TopGlowBackgroundState();
}

class _TopGlowBackgroundState extends State<TopGlowBackground> {
  /// The glow's top-left; [TopGlowBackdrop] aligns its copy to this box.
  final _origin = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final geometry = TopGlowGeometry.forWidth(MediaQuery.sizeOf(context).width);
    final image = TopGlowRaster.imageFor(geometry);
    final color = widget.color;
    Widget result = Stack(
      key: _origin,
      fit: StackFit.expand,
      children: [
        Positioned(
          top: 0,
          left: 0,
          width: geometry.frame.width,
          height: geometry.frame.height,
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                key: TopGlowBackground.glowKey,
                size: geometry.frame,
                painter: _GlowPainter(image),
              ),
            ),
          ),
        ),
        _TopGlowScope(
          image: image,
          frame: geometry.frame,
          color: color ?? Theme.of(context).scaffoldBackgroundColor,
          origin: _origin,
          child: widget.child,
        ),
      ],
    );
    if (color != null) {
      result = ColoredBox(color: color, child: result);
    }
    // Light status-bar icons over the orange glow.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: result,
    );
  }
}

class _TopGlowScope extends InheritedWidget {
  const _TopGlowScope({
    required this.image,
    required this.frame,
    required this.color,
    required this.origin,
    required super.child,
  });

  final ui.Image image;
  final Size frame;
  final Color color;
  final GlobalKey origin;

  static _TopGlowScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TopGlowScope>();

  @override
  bool updateShouldNotify(_TopGlowScope old) =>
      old.image != image ||
      old.frame != frame ||
      old.color != color ||
      old.origin != origin;
}

/// Paints, behind [child], exactly what the enclosing [TopGlowBackground]
/// shows at this spot (page color + the fixed glow), so a bar that must hide
/// content scrolling under it still looks see-through, with no seam.
///
/// [fadeExtent] adds a soft fade below the box (same backdrop, fading to
/// transparent) so content slides out from under it without a hard edge.
/// With [fadeWhenPinned] the fade only appears as the box reaches the top of
/// its scroll view (a pinned header), so it never dims content at rest.
///
/// Painted from the cached glow image: no blur and no saveLayer outside the
/// small fade strip.
class TopGlowBackdrop extends SingleChildRenderObjectWidget {
  const TopGlowBackdrop({
    super.key,
    super.child,
    this.fadeExtent = 0,
    this.fadeWhenPinned = false,
  });

  final double fadeExtent;
  final bool fadeWhenPinned;

  @override
  RenderTopGlowBackdrop createRenderObject(BuildContext context) {
    final scope = _TopGlowScope.maybeOf(context);
    return RenderTopGlowBackdrop(
      color: scope?.color ?? Theme.of(context).scaffoldBackgroundColor,
      image: scope?.image,
      frame: scope?.frame ?? Size.zero,
      origin: scope?.origin,
      fadeExtent: fadeExtent,
      fadeWhenPinned: fadeWhenPinned,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderTopGlowBackdrop renderObject,
  ) {
    final scope = _TopGlowScope.maybeOf(context);
    renderObject
      ..color = scope?.color ?? Theme.of(context).scaffoldBackgroundColor
      ..image = scope?.image
      ..frame = scope?.frame ?? Size.zero
      ..origin = scope?.origin
      ..fadeExtent = fadeExtent
      ..fadeWhenPinned = fadeWhenPinned;
  }
}

/// Wraps a scroll area that starts below a see-through top bar (or the
/// status bar) so its content fades out at the top edge over the glow
/// instead of being cut off in a hard line. The fade sits in the content's
/// top padding at rest, so it only shows on scrolled content.
class TopGlowEdgeFade extends StatelessWidget {
  const TopGlowEdgeFade({super.key, required this.child, this.extent = 16});

  final Widget child;
  final double extent;

  static const fadeKey = ValueKey('top-glow-edge-fade');

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      child,
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: TopGlowBackdrop(
            key: fadeKey,
            fadeExtent: extent,
            child: const SizedBox(width: double.infinity),
          ),
        ),
      ),
    ],
  );
}

class RenderTopGlowBackdrop extends RenderProxyBox {
  RenderTopGlowBackdrop({
    required this._color,
    required this._image,
    required this._frame,
    required this._origin,
    required this._fadeExtent,
    required this._fadeWhenPinned,
  });

  Color _color;
  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  ui.Image? _image;
  set image(ui.Image? value) {
    if (value == _image) return;
    _image = value;
    markNeedsPaint();
  }

  Size _frame;
  set frame(Size value) {
    if (value == _frame) return;
    _frame = value;
    markNeedsPaint();
  }

  GlobalKey? _origin;
  set origin(GlobalKey? value) {
    if (value == _origin) return;
    _origin = value;
    markNeedsPaint();
  }

  double _fadeExtent;
  set fadeExtent(double value) {
    if (value == _fadeExtent) return;
    _fadeExtent = value;
    markNeedsPaint();
  }

  bool _fadeWhenPinned;
  set fadeWhenPinned(bool value) {
    if (value == _fadeWhenPinned) return;
    _fadeWhenPinned = value;
    markNeedsPaint();
  }

  /// Where the glow frame's top-left sits in this box's coordinates.
  @visibleForTesting
  Offset? get glowOffset {
    final box = _origin?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) - localToGlobal(Offset.zero);
  }

  /// 0..1: how strongly the fade below the box shows.
  @visibleForTesting
  double get fadeStrength {
    if (_fadeExtent <= 0) return 0;
    if (!_fadeWhenPinned) return 1;
    final viewport = RenderAbstractViewport.maybeOf(this);
    if (viewport is! RenderBox) return 1;
    final gap =
        localToGlobal(Offset.zero).dy -
        (viewport as RenderBox).localToGlobal(Offset.zero).dy;
    return (1 - gap / _fadeExtent).clamp(0.0, 1.0);
  }

  void _paintBackdrop(Canvas canvas, Rect area, Offset offset) {
    canvas
      ..save()
      ..clipRect(area)
      ..drawRect(area, Paint()..color = _color);
    final image = _image;
    final glow = glowOffset;
    if (image != null && glow != null) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        (offset + glow) & _frame,
        Paint()..filterQuality = FilterQuality.low,
      );
    }
    canvas.restore();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    if (!size.isEmpty) _paintBackdrop(canvas, offset & size, offset);
    final strength = fadeStrength;
    if (strength > 0) {
      final fade = Rect.fromLTWH(
        offset.dx,
        offset.dy + size.height,
        size.width,
        _fadeExtent,
      );
      canvas.saveLayer(fade, Paint());
      _paintBackdrop(canvas, fade, offset);
      canvas.drawRect(
        fade,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: strength),
              Colors.transparent,
            ],
          ).createShader(fade),
      );
      canvas.restore();
    }
    super.paint(context, offset);
  }
}

/// Glow geometry for one screen width: the Figma 390×391 frame scaled
/// linearly by `width / 390`.
@immutable
class TopGlowGeometry {
  TopGlowGeometry.forWidth(double screenWidth)
    : scale = AppSizes.widthScale(screenWidth);

  final double scale;

  Size get frame => Size(390 * scale, 391 * scale);
  Rect get circle =>
      Rect.fromLTWH(-25 * scale, -91 * scale, 182 * scale, 182 * scale);
  double get sigma =>
      TopGlowBackground.figmaLayerBlur * TopGlowBackground.blurToSigma * scale;

  @override
  bool operator ==(Object other) =>
      other is TopGlowGeometry && other.scale == scale;

  @override
  int get hashCode => scale.hashCode;
}

/// Rasterized blurred circles, one per (rounded) screen scale.
class TopGlowRaster {
  TopGlowRaster._();

  static final _cache = <int, ui.Image>{};

  /// Number of blur rasterizations so far (tests assert it stays at one).
  @visibleForTesting
  static int debugRasterCount = 0;

  static ui.Image imageFor(TopGlowGeometry geometry) =>
      _cache[(geometry.scale * 100).round()] ??= _rasterize(geometry);

  static ui.Image _rasterize(TopGlowGeometry geometry) {
    debugRasterCount++;
    // Only the visible frame is rasterized (the Figma frame clips the glow).
    final frame = geometry.frame;
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawOval(
      geometry.circle,
      Paint()
        ..color = TopGlowBackground.glowColor
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, geometry.sigma),
    );
    final picture = recorder.endRecording();
    // Logical resolution is plenty: the blur leaves no detail to lose.
    final image = picture.toImageSync(frame.width.ceil(), frame.height.ceil());
    picture.dispose();
    return image;
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    final image = this.image;
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    canvas.drawImageRect(
      image,
      src,
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.image != image;
}
