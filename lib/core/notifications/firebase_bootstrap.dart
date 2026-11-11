import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Core initialization for the Firebase-configured platforms (iOS, Android).
/// Messaging permission/token/session flows consume this shared readiness gate.
class FirebaseBootstrap {
  FirebaseBootstrap({
    TargetPlatform? platform,
    bool? isWeb,
    Future<void> Function()? initializeCore,
    void Function(Object error)? onError,
  }) : _platform = platform ?? defaultTargetPlatform,
       _isWeb = isWeb ?? kIsWeb,
       _initializeCore = initializeCore ?? _initializeNative,
       _onError = onError ?? _reportError;

  static final instance = FirebaseBootstrap();
  static const _configured = {TargetPlatform.iOS, TargetPlatform.android};
  final TargetPlatform _platform;
  final bool _isWeb;
  final Future<void> Function() _initializeCore;
  final void Function(Object error) _onError;
  Future<bool>? _pending;

  /// Coalesces all callers and caches success/failure for this app process.
  /// Returns false for unconfigured platforms or a failed native initialization.
  Future<bool> initialize() => _pending ??= _initialize();

  Future<bool> _initialize() async {
    if (_isWeb || !_configured.contains(_platform)) return false;
    try {
      await _initializeCore();
      return true;
    } catch (error) {
      _onError(error);
      return false;
    }
  }

  static Future<void> _initializeNative() async {
    // Native options come from the bundled iOS GoogleService plist or the
    // Android google-services.json resources.
    // Reuse a default app if native startup or another owner already made it.
    if (!Firebase.apps.any((app) => app.name == '[DEFAULT]')) {
      await Firebase.initializeApp();
    }
  }

  static void _reportError(Object error) {
    final code = error is FirebaseException ? error.code : error.runtimeType;
    // Do not log token values, payloads, or potentially sensitive error details.
    debugPrint('Firebase Core initialization failed ($code).');
  }
}
