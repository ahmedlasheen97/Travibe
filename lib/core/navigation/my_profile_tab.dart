import 'package:flutter/foundation.dart';

/// How any route (sheets and pushed screens included, which cannot see
/// Root's widgets) shows the signed-in user's own Profile tab. Root attaches
/// its tab switcher; without Root (tests, isolated screens) [show] is false.
abstract final class MyProfileTab {
  static Object? _owner;
  static VoidCallback? _show;

  static void attach(Object owner, VoidCallback show) {
    _owner = owner;
    _show = show;
  }

  static void detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _show = null;
  }

  /// Returns false when no Root is attached.
  static bool show() {
    final show = _show;
    if (show == null) return false;
    show();
    return true;
  }
}
