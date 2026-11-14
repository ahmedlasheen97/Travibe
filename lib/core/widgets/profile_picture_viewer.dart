import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';

/// Opens [imageUrl] full screen over the current route.
Future<void> openProfilePictureViewer(BuildContext context, String imageUrl) =>
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        fullscreenDialog: true,
        barrierColor: Colors.transparent,
        pageBuilder: (_, _, _) => ProfilePictureViewer(imageUrl: imageUrl),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );

/// Full-screen profile picture: pinch to zoom, swipe down (when not zoomed)
/// or the back button to close.
class ProfilePictureViewer extends StatefulWidget {
  const ProfilePictureViewer({super.key, required this.imageUrl});

  final String imageUrl;

  /// Drag distance (logical px) past which a release closes the viewer.
  static const dismissDistance = 120.0;

  @override
  State<ProfilePictureViewer> createState() => _ProfilePictureViewerState();
}

class _ProfilePictureViewerState extends State<ProfilePictureViewer>
    with SingleTickerProviderStateMixin {
  final _zoom = TransformationController();
  late final AnimationController _settle;
  bool _wasZoomed = false;
  double _drag = 0;
  double _settleFrom = 0;
  bool _closing = false;

  bool get _zoomed => _zoom.value.getMaxScaleOnAxis() > 1.01;

  // Rebuild when crossing the zoomed threshold so the dismiss drag turns
  // off (pan wins) or back on.
  void _zoomChanged() {
    if (_zoomed != _wasZoomed) setState(() => _wasZoomed = _zoomed);
  }

  @override
  void initState() {
    super.initState();
    _zoom.addListener(_zoomChanged);
    _settle =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 180),
        )..addListener(
          () => setState(() => _drag = _settleFrom * (1 - _settle.value)),
        );
  }

  @override
  void dispose() {
    _zoom.dispose();
    _settle.dispose();
    super.dispose();
  }

  void _update(DragUpdateDetails details) {
    if (_closing) return;
    _settle.stop();
    setState(
      () => _drag = (_drag + details.delta.dy).clamp(0, double.infinity),
    );
  }

  void _end(DragEndDetails details) {
    if (_closing) return;
    final fling = (details.primaryVelocity ?? 0) > 700;
    if (fling || _drag > ProfilePictureViewer.dismissDistance) {
      _closing = true;
      Navigator.of(context).maybePop();
      return;
    }
    _settleFrom = _drag;
    _settle.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final fade = (1 - _drag / 400).clamp(0.3, 1.0);
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: fade),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('profile-picture-drag'),
              behavior: HitTestBehavior.opaque,
              // Off while zoomed so panning the picture wins the gesture.
              onVerticalDragUpdate: _zoomed ? null : _update,
              onVerticalDragEnd: _zoomed ? null : _end,
              child: Transform.translate(
                offset: Offset(0, _drag),
                child: InteractiveViewer(
                  transformationController: _zoom,
                  minScale: 1,
                  maxScale: 5,
                  child: Center(
                    child: Image.network(
                      widget.imageUrl,
                      key: const ValueKey('profile-picture-image'),
                      fit: BoxFit.contain,
                      loadingBuilder: (_, child, progress) => progress == null
                          ? child
                          : const CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                      errorBuilder: (_, _, _) => Icon(
                        Icons.person_rounded,
                        color: Colors.white54,
                        size: AppSizes.w56,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(AppSizes.adaptiveWidth(16)),
                child: const BackButtonWidget(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
