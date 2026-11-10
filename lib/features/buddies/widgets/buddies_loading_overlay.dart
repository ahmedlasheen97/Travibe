import 'package:flutter/material.dart';
import 'package:travibe/core/widgets/travibe_loading_indicator.dart';

/// Paint only: no loading slot, scroll extent or content padding.
class BuddiesLoadingOverlay extends StatelessWidget {
  const BuddiesLoadingOverlay({
    super.key,
    required this.loading,
    required this.child,
  });
  final bool loading;
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      child,
      if (loading)
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: TravibeLoadingIndicator(
                size: 30,
                semanticsLabel: 'Loading buddies',
              ),
            ),
          ),
        ),
    ],
  );
}
