import 'package:flutter/widgets.dart';

/// Always scrollable, so pull-to-refresh works even when the content is
/// shorter than the screen, with the platform's native feel: iOS (and macOS)
/// bounce and decelerate like UIKit lists; Android clamps.
///
/// The platform comes from the scroll behavior (as Flutter's own default
/// physics do), not from a cached ThemeData.
ScrollPhysics platformRefreshPhysics(BuildContext context) =>
    AlwaysScrollableScrollPhysics(
      parent: switch (ScrollConfiguration.of(context).getPlatform(context)) {
        TargetPlatform.iOS ||
        TargetPlatform.macOS => const BouncingScrollPhysics(),
        _ => const ClampingScrollPhysics(),
      },
    );
