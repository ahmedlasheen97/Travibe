import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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
  const TopGlowBackground({
    super.key,
    required this.child,
    this.color,
    this.fadeOnScroll = false,
    this.fadeDistance = 120,
  });

  final Widget child;

  /// Fades the glow (and every [TopGlowBackdrop] copy) out as the child's
  /// primary vertical scroll view scrolls down, fully hidden after
  /// [fadeDistance], and back in towards the top. Driven by scroll
  /// notifications into a repaint-only listenable: no widget rebuilds and no
  /// re-blur (the cached image is painted with a lower alpha).
  final bool fadeOnScroll;
  final double fadeDistance;

  /// Optional page background painted under the glow (screens that own a
  /// Scaffold pass its color and make the Scaffold transparent). Without it
  /// the theme's scaffold color is assumed for [TopGlowBackdrop].
  final Color? color;

  /// Fitted to the Figma Home render (docs/figma/home/home_glow_reference.png
  /// on #0A0A0A): a soft dark brown, ≈(36,22,13) at the clock and
  /// ≈(31,20,12) behind "Hello", within ±2 per channel at every sampled
  /// point (test/core/widgets/top_glow_figma_match_test.dart). The token
  /// #E45C10 at 84% rendered ≈(50,25,11) there — far too orange.
  static const glowColor = Color(0x8BE46E1E);

  /// Figma layer blur.
  static const figmaLayerBlur = 150.0;

  /// Gaussian σ per unit of Figma blur (σ ≈ 135 at 390 wide); the falloff
  /// matches the Home reference out to y ≈ 260 with [glowColor].
  static const blurToSigma = 0.9;

  static const glowKey = ValueKey('top-glow');

  /// The current glow opacity (1 at rest) for the enclosing background.
  static ValueListenable<double>? opacityOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_TopGlowScope>()?.opacity;

  @override
  State<TopGlowBackground> createState() => _TopGlowBackgroundState();
}

class _TopGlowBackgroundState extends State<TopGlowBackground> {
  /// The glow's top-left; [TopGlowBackdrop] aligns its copy to this box.
  final _origin = GlobalKey();
  final _opacity = ValueNotifier<double>(1);

  bool _onScroll(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (notification.depth != 0 || metrics.axis != Axis.vertical) {
      return false;
    }
    final distance = widget.fadeDistance;
    final scrolled = (metrics.pixels - metrics.minScrollExtent).clamp(
      0.0,
      distance,
    );
    _opacity.value = 1 - scrolled / distance;
    return false;
  }

  @override
  void didUpdateWidget(TopGlowBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.fadeOnScroll) _opacity.value = 1;
  }

  @override
  void dispose() {
    _opacity.dispose();
    super.dispose();
  }

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
                painter: _GlowPainter(image, _opacity),
              ),
            ),
          ),
        ),
        _TopGlowScope(
          image: image,
          frame: geometry.frame,
          color: color ?? Theme.of(context).scaffoldBackgroundColor,
          origin: _origin,
          opacity: _opacity,
          child: widget.fadeOnScroll
              ? NotificationListener<ScrollNotification>(
                  onNotification: _onScroll,
                  child: widget.child,
                )
              : widget.child,
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
    required this.opacity,
    required super.child,
  });

  final ui.Image image;
  final Size frame;
  final Color color;
  final GlobalKey origin;
  final ValueListenable<double> opacity;

  static _TopGlowScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TopGlowScope>();

  @override
  bool updateShouldNotify(_TopGlowScope old) =>
      old.image != image ||
      old.frame != frame ||
      old.color != color ||
      old.origin != origin ||
      old.opacity != opacity;
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
      opacity: scope?.opacity,
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
      ..opacity = scope?.opacity
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
    this._opacity,
  });

  ValueListenable<double>? _opacity;
  set opacity(ValueListenable<double>? value) {
    if (value == _opacity) return;
    if (attached) _opacity?.removeListener(markNeedsPaint);
    _opacity = value;
    if (attached) _opacity?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  /// The glow alpha this copy paints with (follows the main glow's fade).
  @visibleForTesting
  double get glowOpacity => _opacity?.value ?? 1;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _opacity?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _opacity?.removeListener(markNeedsPaint);
    super.detach();
  }

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
    final alpha = glowOpacity;
    if (image != null && glow != null && alpha > 0) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        (offset + glow) & _frame,
        Paint()
          ..filterQuality = FilterQuality.low
          ..color = Color.fromRGBO(0, 0, 0, alpha),
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
  _GlowPainter(this.image, this.opacity) : super(repaint: opacity);

  final ui.Image image;

  /// Repaint-only fade (scroll): the cached image is drawn with this alpha.
  final ValueListenable<double> opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final alpha = opacity.value;
    if (alpha <= 0) return;
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
      Paint()
        ..filterQuality = FilterQuality.low
        ..color = Color.fromRGBO(0, 0, 0, alpha),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) =>
      old.image != image || old.opacity != opacity;
}
