import 'dart:async';
import 'package:flutter/foundation.dart';

/// App-wide "retry failed images" signal. Home bumps it on reconnect/Refresh;
/// images that failed to load re-request when the generation changes.
///
/// Images also report their failures here, so Home can watch for the
/// connection to return even when only images failed (no toast).
class ImageRetrySignal extends ValueNotifier<int> {
  ImageRetrySignal() : super(0);
  static final instance = ImageRetrySignal();

  final _failed = <Object>{};

  /// Number of currently failed images (updated in a microtask, so reports
  /// made while building never notify listeners mid-build).
  final failedCount = ValueNotifier<int>(0);

  bool _manual = false;

  /// Whether the latest [bump] came from the user (Refresh/pull-to-refresh).
  /// Manual retries ignore the per-image automatic attempt cap.
  bool get lastBumpManual => _manual;

  void bump({bool manual = false}) {
    _manual = manual;
    value++;
  }

  void reportFailed(Object image) {
    if (_failed.add(image)) _publish();
  }

  /// Loaded, replaced or disposed: no longer waiting for a retry.
  void reportResolved(Object image) {
    if (_failed.remove(image)) _publish();
  }

  void _publish() => scheduleMicrotask(() {
    failedCount.value = _failed.length;
  });

  @visibleForTesting
  void reset() {
    _failed.clear();
    failedCount.value = 0;
  }

  @override
  void dispose() {
    failedCount.dispose();
    super.dispose();
  }
}
