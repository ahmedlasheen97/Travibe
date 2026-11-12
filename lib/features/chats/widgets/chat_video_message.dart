import 'package:travibe/core/widgets/app_loaders.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import '../cubit/chat_audio_controller.dart';

/// Explicit user-initiated playback; no URL loads or autoplay at row creation.
class ChatVideoMessage extends StatefulWidget {
  const ChatVideoMessage({
    super.key,
    required this.url,
    this.audio,
    this.width = 220,
    this.maxHeight,
  });
  final Uri? url;
  final double width;
  final double? maxHeight;
  final ChatAudioController? audio;
  @override
  State<ChatVideoMessage> createState() => _ChatVideoMessageState();
}

class _ChatVideoMessageState extends State<ChatVideoMessage>
    with WidgetsBindingObserver {
  final _preferences = PreferencesManager();
  late final int _session;
  VideoPlayerController? _controller;
  bool _busy = false, _error = false;
  bool _foreground = true;
  bool get _valid =>
      mounted &&
      _preferences.hasSession &&
      _session == _preferences.sessionRevision;
  @override
  void initState() {
    super.initState();
    _session = _preferences.sessionRevision;
    _preferences.addListener(_accountChanged);
    WidgetsBinding.instance.addObserver(this);
    widget.audio?.registerVideoPause(_pause);
  }

  void _accountChanged() {
    final player = _controller;
    _controller = null;
    if (player != null) {
      unawaited(player.dispose());
    }
    if (mounted) setState(() {});
  }

  void _changed() {
    if (_valid) {
      setState(() {
        if (_controller?.value.hasError == true) _error = true;
      });
    }
  }

  Future<void> _pause() async {
    try {
      await _controller?.pause();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) unawaited(_pause());
  }

  Future<void> _toggle() async {
    final url = widget.url;
    if (!_valid ||
        !_foreground ||
        widget.audio?.recording == true ||
        _busy ||
        url == null ||
        url.scheme != 'https' ||
        url.host.isEmpty) {
      return;
    }
    _busy = true;
    setState(() => _error = false);
    try {
      if (_controller?.value.hasError == true) {
        final failed = _controller;
        _controller = null;
        try {
          await failed?.dispose();
        } catch (_) {}
      }
      if (_controller == null) {
        final player = VideoPlayerController.networkUrl(url);
        _controller = player;
        player.addListener(_changed);
        await player.initialize();
        if (!_valid || !_foreground) {
          if (identical(_controller, player)) _controller = null;
          player.removeListener(_changed);
          await player.dispose();
          return;
        }
      }
      final player = _controller!;
      if (player.value.isPlaying) {
        await player.pause();
      } else {
        await widget.audio?.stopPlayback();
        await widget.audio?.pauseVideos();
        if (!_valid || !_foreground) return;
        if (player.value.position >= player.value.duration) {
          await player.seekTo(Duration.zero);
        }
        await player.play();
      }
    } catch (_) {
      if (_valid) {
        _error = true;
        final player = _controller;
        _controller = null;
        try {
          await player?.dispose();
        } catch (_) {}
      }
    } finally {
      _busy = false;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _preferences.removeListener(_accountChanged);
    WidgetsBinding.instance.removeObserver(this);
    widget.audio?.unregisterVideoPause(_pause);
    final player = _controller;
    if (player != null) {
      player.removeListener(_changed);
      unawaited(player.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_valid || widget.url == null) {
      return const Text(
        'Video unavailable',
        style: TextStyle(color: Colors.white60),
      );
    }
    final player = _controller;
    return SizedBox(
      width: widget.width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (player != null && player.value.isInitialized)
            SizedBox(
              height:
                  (widget.width /
                          (player.value.aspectRatio > 0
                              ? player.value.aspectRatio
                              : 1))
                      .clamp(
                        1.0,
                        widget.maxHeight == null
                            ? double.infinity
                            : (widget.maxHeight! - 56).clamp(
                                1.0,
                                double.infinity,
                              ),
                      ),
              child: Center(
                child: AspectRatio(
                  aspectRatio: player.value.aspectRatio > 0
                      ? player.value.aspectRatio
                      : 1,
                  child: VideoPlayer(player),
                ),
              ),
            ),
          if (_error)
            const Text(
              'Unable to play this video.',
              style: TextStyle(color: Colors.white60),
            ),
          Row(
            children: [
              IconButton(
                tooltip: player?.value.isPlaying == true
                    ? 'Pause video'
                    : 'Play video',
                onPressed: _busy ? null : _toggle,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: AppActivityIndicator(),
                      )
                    : Icon(
                        player?.value.isPlaying == true
                            ? Icons.pause
                            : Icons.play_arrow,
                        color: Colors.white,
                      ),
              ),
              const Expanded(
                child: Text('Video', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
