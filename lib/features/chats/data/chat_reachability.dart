import 'package:flutter/foundation.dart';

/// Positive evidence of connectivity: any HTTP response from the chat API.
/// Lets the offline banner recover when the platform interface status is stale.
class ChatReachability extends ChangeNotifier {
  ChatReachability({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  static final instance = ChatReachability();
  final DateTime Function() _clock;
  DateTime? _lastSuccess;
  DateTime? get lastSuccess => _lastSuccess;

  void markReachable() {
    _lastSuccess = _clock();
    notifyListeners();
  }

  @visibleForTesting
  void reset() => _lastSuccess = null;

  bool reachedWithin(Duration window) {
    final last = _lastSuccess;
    return last != null && _clock().difference(last) < window;
  }
}
