import 'package:flutter/material.dart';
import 'package:travibe/core/widgets/app_loaders.dart';

/// White determinate ring used by the floating upload toasts (stories,
/// profile pictures).
class UploadProgressRing extends StatelessWidget {
  const UploadProgressRing({super.key, required this.progress, this.ringKey});

  /// 0..1; 0 shows an indeterminate spinner while a file is prepared.
  final double progress;
  final Key? ringKey;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Upload ${(progress * 100).round()}%',
    child: progress <= 0
        ? const AppActivityIndicator(radius: 10)
        : CircularProgressIndicator(
            key: ringKey,
            value: progress.clamp(0.0, 1.0),
            strokeWidth: 2.5,
            color: appLoaderColor,
            backgroundColor: Colors.white24,
          ),
  );
}
