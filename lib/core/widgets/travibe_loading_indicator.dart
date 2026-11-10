import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Theme;

/// Home's native activity indicator, colored by the existing Travibe theme.
class TravibeLoadingIndicator extends StatelessWidget {
  const TravibeLoadingIndicator({
    super.key,
    this.size = 64,
    this.semanticsLabel = 'Loading',
  }) : assert(size > 0 && size < double.infinity);

  final double size;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticsLabel,
    liveRegion: true,
    excludeSemantics: true,
    child: SizedBox.square(
      dimension: size,
      child: Center(
        child: CupertinoActivityIndicator(
          color: Theme.of(context).primaryColor,
          radius: 15,
          animating: !MediaQuery.disableAnimationsOf(context),
        ),
      ),
    ),
  );
}
