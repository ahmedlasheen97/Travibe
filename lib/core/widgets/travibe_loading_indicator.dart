import 'package:travibe/core/widgets/app_loaders.dart';
import 'package:flutter/cupertino.dart';

/// Home's native activity indicator, white like every app loader.
class TravibeLoadingIndicator extends StatelessWidget {
  const TravibeLoadingIndicator({
    super.key,
    this.size = 64,
    this.semanticsLabel = 'Loading',
    this.color,
  }) : assert(size > 0 && size < double.infinity);

  final double size;
  final String semanticsLabel;

  /// Defaults to [appLoaderColor] (white).
  final Color? color;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticsLabel,
    liveRegion: true,
    excludeSemantics: true,
    child: SizedBox.square(
      dimension: size,
      child: Center(
        child: AppActivityIndicator(
          color: color ?? appLoaderColor,
          radius: 15,
          animating: !MediaQuery.disableAnimationsOf(context),
        ),
      ),
    ),
  );
}
