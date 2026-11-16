import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:travibe/core/widgets/swipe_down_dismiss.dart';

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
/// or the X to close.
class ProfilePictureViewer extends StatefulWidget {
  const ProfilePictureViewer({super.key, required this.imageUrl});

  final String imageUrl;

  @override
  State<ProfilePictureViewer> createState() => _ProfilePictureViewerState();
}

class _ProfilePictureViewerState extends State<ProfilePictureViewer> {
  final _zoom = TransformationController();
  bool _zoomed = false;

  // Rebuild when crossing the zoomed threshold so the dismiss drag turns
  // off (pan wins) or back on.
  void _zoomChanged() {
    final zoomed = _zoom.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  @override
  void initState() {
    super.initState();
    _zoom.addListener(_zoomChanged);
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: SwipeDownDismiss(
            enabled: !_zoomed,
            onDismiss: () => Navigator.of(context).maybePop(),
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
        PositionedDirectional(
          top: 0,
          start: 0,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(AppSizes.adaptiveWidth(16)),
              child: const BackButtonWidget.close(),
            ),
          ),
        ),
      ],
    ),
  );
}
