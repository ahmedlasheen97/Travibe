import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:travibe/features/chats/data/chat_reachability.dart';

/// Interface reachability only. A connected interface never proves API health.
/// Unknown/unsupported capabilities do not become a fabricated offline state.
/// A chat API response proves connectivity and clears a stale offline report.
class ChatNetworkBanner extends StatefulWidget {
  const ChatNetworkBanner({
    super.key,
    this.onReconnect,
    this.status,
    this.onStatus,
    this.reachability,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
  });
  final Future<void> Function()? onReconnect;
  final Future<bool?> Function()? status;
  final ValueChanged<bool?>? onStatus;
  final ChatReachability? reachability;
  final EdgeInsetsGeometry margin;
  @override
  State<ChatNetworkBanner> createState() => _ChatNetworkBannerState();
}

class _ChatNetworkBannerState extends State<ChatNetworkBanner>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('travibe/chat_media');
  static const _trustReachable = Duration(seconds: 10);
  static const _probeEvery = 3;
  Timer? _timer, _timeout;
  Completer<bool?>? _response;
  bool? _connected;
  bool _checking = false, _probing = false;
  int _generation = 0, _offlineTicks = 0;
  late final ChatReachability _reachability =
      widget.reachability ?? ChatReachability.instance;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reachability.addListener(_reachable);
    _start();
  }

  void _reachable() {
    if (!mounted || _connected != false) return;
    setState(() => _connected = true);
    widget.onStatus?.call(true);
    unawaited(_reconnect());
  }

  Future<void> _reconnect() async {
    try {
      await widget.onReconnect?.call();
    } catch (_) {}
  }

  /// While offline, periodically retry the reconnect action; a successful
  /// response clears the banner through [ChatReachability].
  Future<void> _probe() async {
    if (_probing || ++_offlineTicks % _probeEvery != 0) return;
    _probing = true;
    try {
      await _reconnect();
    } finally {
      _probing = false;
    }
  }

  void _start() {
    _timer?.cancel();
    unawaited(_check());
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_check()),
    );
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    final generation = _generation;
    try {
      final response = Completer<bool?>();
      _response = response;
      _timeout = Timer(const Duration(seconds: 3), () {
        if (!response.isCompleted) response.complete(null);
      });
      (widget.status?.call() ?? _channel.invokeMethod<bool>('networkStatus'))
          .then(
            (value) {
              if (!response.isCompleted) response.complete(value);
            },
            onError: (Object _) {
              if (!response.isCompleted) response.complete(null);
            },
          );
      var value = await response.future;
      if (!mounted || generation != _generation) return;
      // A recent API response outranks a stale interface report.
      if (value == false && _reachability.reachedWithin(_trustReachable)) {
        value = true;
      }
      final reconnect = _connected == false && value == true;
      // Unknown capability/timeouts must not dismiss confirmed offline state.
      if (value != null) setState(() => _connected = value);
      widget.onStatus?.call(_connected);
      if (_connected != false) _offlineTicks = 0;
      if (reconnect) {
        await _reconnect();
      } else if (_connected == false) {
        unawaited(_probe());
      }
    } catch (_) {
      /* Unknown status; never classify an HTTP failure as offline. */
    } finally {
      _timeout?.cancel();
      _response = null;
      _checking = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ++_generation;
    if (state == AppLifecycleState.resumed) {
      _start();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    ++_generation;
    _timer?.cancel();
    _timeout?.cancel();
    if (_response?.isCompleted == false) _response!.complete(null);
    _reachability.removeListener(_reachable);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Widget _content() => _connected != false
      ? const SizedBox.shrink()
      : Padding(
          padding: widget.margin,
          child: Semantics(
            liveRegion: true,
            child: Container(
              key: const ValueKey('chat-offline-banner'),
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF9F2020),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'No internet connection',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
  @override
  Widget build(BuildContext context) {
    final child = _content();
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.bottomCenter,
      curve: Curves.easeOut,
      child: child,
    );
  }
}
