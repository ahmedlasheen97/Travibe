import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:flutter/material.dart';
import '../data/chat_history_cache.dart';

/// Uses Flutter's shared decoded-image cache; no extra URL resolution request.
/// Dimensions survive route changes for the same signed URL and session.
class ChatHistoryImage extends StatefulWidget {
  const ChatHistoryImage({super.key, required this.url, this.aspectRatio});
  final Uri url;
  final double? aspectRatio;
  @override
  State<ChatHistoryImage> createState() => _ChatHistoryImageState();
}

class _ChatHistoryImageState extends State<ChatHistoryImage> {
  final _session = PreferencesManager().sessionRevision;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? _image;
  bool _failed = false;
  double _ratio = 1;
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
    await NetworkImage(widget.url.toString()).evict();
    if (!mounted || _session != PreferencesManager().sessionRevision) return;
    _detach();
    _stream = null;
    setState(_resolve);
  }

  void _detach() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
  }

  @override
  void dispose() {
    _detach();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ratio = _ratio;
    final width = (360 * ratio).clamp(1.0, 220.0);
    final height = width / ratio;
    return SizedBox(
      width: width,
      height: height,
      child: _failed
          ? Center(
              child: TextButton(
                onPressed: _retry,
                child: const Text('Image unavailable. Retry'),
              ),
            )
          : _image == null
          ? Semantics(
              label: 'Loading image',
              child: const ColoredBox(
                key: ValueKey('chat-image-download-placeholder'),
                color: Color(0xFF202020),
              ),
            )
          : RawImage(image: _image!.image, fit: BoxFit.contain),
    );
  }
}
