import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:flutter/material.dart';
import '../data/chat_history_cache.dart';
import '../data/chat_reachability.dart';

/// Uses Flutter's shared decoded-image cache; no extra URL resolution request.
/// Dimensions survive route changes for the same signed URL and session.
/// A failed load retries on tap and when [ChatReachability] reports the chat
/// API reachable again (the same signal that clears the offline banner).
class ChatHistoryImage extends StatefulWidget {
  const ChatHistoryImage({
    super.key,
    required this.url,
    this.aspectRatio,
    this.reachability,
    this.width,
    this.maxHeight,
  });
  final Uri url;
  final double? aspectRatio;

  /// Fixed width; the image then keeps its ratio up to [maxHeight] and is
  /// cropped (cover) beyond it. Null keeps the default 220px chat sizing.
  final double? width, maxHeight;
  final ChatReachability? reachability;
  @override
  State<ChatHistoryImage> createState() => _ChatHistoryImageState();
}

class _ChatHistoryImageState extends State<ChatHistoryImage> {
  final _session = PreferencesManager().sessionRevision;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? _image;
  bool _failed = false, _retrying = false;
  DateTime? _lastAutoRetry;
  double _ratio = 1;
  late final ChatReachability _reachability =
      widget.reachability ?? ChatReachability.instance;
  @override
  void initState() {
    super.initState();
    _reachability.addListener(_reachable);
  }

  void _reachable() {
    // Every API response notifies; throttle so a permanently broken URL is not
    // re-requested on each one.
    final now = DateTime.now();
    if (!_failed ||
        _lastAutoRetry != null &&
            now.difference(_lastAutoRetry!) < const Duration(seconds: 10)) {
      return;
    }
    _lastAutoRetry = now;
    _retry();
  }

  double? get _metadataRatio =>
      widget.aspectRatio != null &&
          widget.aspectRatio!.isFinite &&
          widget.aspectRatio! > 0
      ? widget.aspectRatio
      : null;
  Object get _key => ('image_geometry', widget.url.toString());
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(ChatHistoryImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _resolve();
    } else if (oldWidget.aspectRatio != widget.aspectRatio &&
        _metadataRatio != null) {
      _ratio = _metadataRatio!;
    }
  }

  void _resolve() {
    final next = NetworkImage(
      widget.url.toString(),
    ).resolve(createLocalImageConfiguration(context));
    if (_stream?.key == next.key) return;
    _detach();
    _failed = false;
    _image?.dispose();
    _image = null;
    _ratio =
        _metadataRatio ?? ChatHistoryCache.instance.read<double>(_key) ?? 1;
    _stream = next;
    chatLoadDiagnostic('image_resolve');
    _listener = ImageStreamListener(
      (info, synchronous) {
        _image?.dispose();
        _image = info;
        final decodedRatio = info.image.width / info.image.height;
        if (synchronous && _metadataRatio == null) _ratio = decodedRatio;
        ChatHistoryCache.instance.write(_key, decodedRatio, _session);
        chatLoadDiagnostic(
          synchronous ? 'image_cache_hit' : 'image_frame_ready',
        );
        if (!synchronous && mounted) setState(() {});
      },
      onError: (Object _, StackTrace? _) {
        if (mounted) setState(() => _failed = true);
        chatLoadDiagnostic('image_error');
      },
    );
    next.addListener(_listener!);
  }

  Future<void> _retry() async {
    if (_retrying) return;
    _retrying = true;
    try {
      await NetworkImage(widget.url.toString()).evict();
      if (!mounted || _session != PreferencesManager().sessionRevision) return;
      _detach();
      _stream = null;
      setState(_resolve);
    } finally {
      _retrying = false;
    }
  }

  void _detach() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
  }

  @override
  void dispose() {
    _reachability.removeListener(_reachable);
    _detach();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ratio = _ratio;
    final fixedWidth = widget.width;
    final width = fixedWidth ?? (360 * ratio).clamp(1.0, 220.0);
    final height = fixedWidth == null
        ? width / ratio
        : (width / ratio).clamp(1.0, widget.maxHeight ?? double.infinity);
    return SizedBox(
      width: width,
      height: height,
      child: _failed
          ? _FailedImage(onRetry: _retry)
          : _image == null
          ? Semantics(
              label: 'Loading image',
              child: const ColoredBox(
                key: ValueKey('chat-image-download-placeholder'),
                color: Color(0xFF202020),
              ),
            )
          : RawImage(
              image: _image!.image,
              fit: fixedWidth == null ? BoxFit.contain : BoxFit.cover,
            ),
    );
  }
}

/// Keeps the bubble geometry; tapping anywhere (or the icon) retries loading.
class _FailedImage extends StatelessWidget {
  const _FailedImage({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Image failed to load',
    child: GestureDetector(
      key: const ValueKey('chat-image-failed-placeholder'),
      behavior: HitTestBehavior.opaque,
      onTap: onRetry,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF202020),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          children: [
            const Center(
              child: Icon(
                Icons.image_outlined,
                color: Colors.white24,
                size: 40,
              ),
            ),
            Positioned(
              right: 4,
              bottom: 4,
              child: IconButton(
                tooltip: 'Retry image',
                onPressed: onRetry,
                iconSize: 18,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white70,
                  minimumSize: const Size.square(32),
                  maximumSize: const Size.square(32),
                  padding: EdgeInsets.zero,
                ),
                icon: const Icon(Icons.refresh),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
