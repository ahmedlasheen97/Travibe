import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/theme/dark_colors.dart';

/// A finite branding animation. Routing remains the caller's responsibility.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onComplete});

  static const symbolAsset = 'assets/images/onboarding/logo1.svg';
  static const wordmarkAsset = 'assets/images/onboarding/logo2.svg';
  static const duration = Duration(milliseconds: 1500);

  final VoidCallback onComplete;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: SplashScreen.duration,
  )..addStatusListener(_statusChanged);
  late final Animation<double> _turns = _controller.drive(
    CurveTween(curve: const Interval(0, .4)),
  );
  bool _preloading = false;
  bool _ready = false;
  bool _completed = false;
  bool _reducedMotion = false;
  bool _active = true;
  late final Widget _symbol = SvgPicture.asset(
    SplashScreen.symbolAsset,
    width: 119,
    height: 108,
  );
  late final Widget _wordmark = SvgPicture.asset(
    SplashScreen.wordmarkAsset,
    width: 182,
    height: 43,
  );

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _active = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (_reducedMotion && _ready) {
      _controller.stop();
      WidgetsBinding.instance.addPostFrameCallback((_) => _complete());
    }
    if (!_preloading) {
      _preloading = true;
      _precache();
    }
  }

  Future<void> _precache() async {
    // SvgAssetLoader uses flutter_svg's shared compiled-picture cache.
    try {
      await Future.wait([
        const SvgAssetLoader(SplashScreen.symbolAsset).loadBytes(context),
        const SvgAssetLoader(SplashScreen.wordmarkAsset).loadBytes(context),
      ]);
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'Travibe splash assets',
        ),
      );
    }
    if (!mounted) return;
    _ready = true;
    if (_reducedMotion) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) => _complete());
    } else if (_active) {
      _controller.forward();
    }
  }

  void _statusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      // Paint the fully orange frame before replacing the route.
      WidgetsBinding.instance.addPostFrameCallback((_) => _complete());
    }
  }

  void _complete() {
    if (!mounted || _completed || !_active) return;
    _completed = true;
    widget.onComplete();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (!_active) {
      _controller.stop();
    } else if (_ready && !_completed) {
      if (_reducedMotion || _controller.isCompleted) {
        _complete();
      } else {
        _controller.forward();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  double _phase(double value, double start, double end) =>
      ((value - start) / (end - start)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.black,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Semantics(
          label: 'Travibe',
          image: true,
          child: ExcludeSemantics(
            child: LayoutBuilder(
              builder: (context, constraints) => AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final t =
                      _controller.value * SplashScreen.duration.inMilliseconds;
                  final rise = _reducedMotion
                      ? 1.0
                      : Curves.easeOutCubic.transform(_phase(t, 0, 600));
                  final brand = _reducedMotion
                      ? 1.0
                      : Curves.easeInOutCubic.transform(_phase(t, 600, 900));
                  final expansion = _reducedMotion
                      ? 0.0
                      : Curves.easeInOutCubic.transform(_phase(t, 900, 1500));
                  final fit = math.max(
                    0.0,
                    math.min(
                      1.0,
                      math.min(
                        (constraints.maxWidth - 48) / 270,
                        (constraints.maxHeight - 48) / 140,
                      ),
                    ),
                  );
                  final viewport = constraints.biggest;
                  final center = viewport.center(Offset.zero);
                  // Entrance is expressed in viewport coordinates, outside any
                  // small logo clipping box. At rest the symbol is upright.
                  final entryY =
                      (viewport.height / 2 + 54 * fit + 1) * (1 - rise);
                  final returnToCenter = _phase(expansion, 0, .4);
                  final symbolOffset = Offset(
                    -98 * brand * fit * (1 - returnToCenter),
                    entryY,
                  );
                  final source = center + symbolOffset;
                  final corners = [
                    Offset.zero,
                    Offset(viewport.width, 0),
                    Offset(0, viewport.height),
                    Offset(viewport.width, viewport.height),
                  ];
                  final coverRadius =
                      corners
                          .map((corner) => (corner - source).distance)
                          .reduce(math.max) +
                      2;
                  final symbolOpacity = 1 - _phase(expansion, .45, .85);
                  final wordmarkOpacity =
                      brand * (1 - _phase(expansion, 0, .2));
                  return ClipRect(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // A circle grows from exactly the SVG's moving center.
                        // It fills its transparent geometry without a rectangle
                        // wipe, and its radius reaches every viewport corner.
                        CustomPaint(
                          key: const ValueKey('splash-orange-expansion'),
                          painter: SplashExpansionPainter(
                            center: source,
                            radius: coverRadius * expansion,
                          ),
                        ),
                        Center(
                          child: Transform.translate(
                            offset: symbolOffset,
                            child: Transform.scale(
                              scale:
                                  fit * (1 - .45 * brand) * (1 + 7 * expansion),
                              child: RotationTransition(
                                key: const ValueKey('splash-symbol-rotation'),
                                turns: _reducedMotion
                                    ? const AlwaysStoppedAnimation(0.0)
                                    : _turns,
                                alignment: Alignment.center,
                                child: Opacity(
                                  key: const ValueKey('splash-symbol'),
                                  opacity: symbolOpacity,
                                  child: _symbol,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Center(
                          child: Transform.translate(
                            offset: Offset((38 + (1 - brand) * 12) * fit, 0),
                            child: Transform.scale(
                              scale: fit,
                              child: Opacity(
                                key: const ValueKey('splash-wordmark'),
                                opacity: wordmarkOpacity,
                                child: _wordmark,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Solid brand orange behind the expanding original SVG. Keeping the circle and
/// SVG on the same center avoids detached transitions and transparent seams.
class SplashExpansionPainter extends CustomPainter {
  const SplashExpansionPainter({required this.center, required this.radius});

  final Offset center;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (radius <= 0) return;
    canvas.drawCircle(center, radius, Paint()..color = DarkColors.primaryColor);
  }

  @override
  bool shouldRepaint(SplashExpansionPainter oldDelegate) =>
      oldDelegate.center != center || oldDelegate.radius != radius;
}
