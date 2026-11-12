import 'package:travibe/core/widgets/app_loaders.dart';
import 'package:flutter/material.dart';
import '../data/chat_models.dart';
import '../widgets/chat_video_message.dart';
import 'package:flutter/services.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:dio/dio.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import '../data/chat_image_saver.dart';
import '../data/chat_device_media.dart';

class ChatImageViewer extends StatefulWidget {
  const ChatImageViewer({
    super.key,
    required this.url,
    this.saver,
    this.media = const [],
    this.initialIndex = 0,
  });
  final Uri url;
  final List<ChatMessage> media;
  final int initialIndex;
  final ChatImageSaver? saver;
  @override
  State<ChatImageViewer> createState() => _ChatImageViewerState();
}

class _ChatImageViewerState extends State<ChatImageViewer> {
  final _preferences = PreferencesManager();
  late final int _session;
  late final _saver = widget.saver ?? ChatImageSaver();
  CancelToken? _cancel;
  bool _saving = false;
  late final List<ChatMessage> _media;
  late final PageController _pages;
  int _index = 0;
  final _thumbnails = ScrollController();
  void _select(int index) {
    setState(() => _index = index);
    if (_thumbnails.hasClients) {
      final target =
          (index * 64 - _thumbnails.position.viewportDimension / 2 + 28).clamp(
            0.0,
            _thumbnails.position.maxScrollExtent,
          );
      _thumbnails.animateTo(
        target,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  Uri get _url => _media[_index].mediaUrl!;
  bool get _video => _media[_index].kind == ChatMessageKind.video;
  bool get _active =>
      mounted &&
      _preferences.hasSession &&
      _session == _preferences.sessionRevision;
  @override
  void initState() {
    super.initState();
    _session = _preferences.sessionRevision;
    _media = widget.media
        .where(
          (m) =>
              !m.isDeleted &&
              (m.kind == ChatMessageKind.image ||
                  m.kind == ChatMessageKind.video) &&
              m.mediaUrl?.scheme == 'https' &&
              m.mediaUrl!.host.isNotEmpty &&
              m.mediaUrl!.userInfo.isEmpty,
        )
        .toList();
    if (_media.isEmpty) {
      _media.add(
        ChatMessage(
          id: 'preview',
          senderId: '',
          kind: ChatMessageKind.image,
          mediaUrl: widget.url,
        ),
      );
    }
    _index = widget.initialIndex.clamp(0, _media.length - 1);
    _pages = PageController(initialPage: _index);
    _preferences.addListener(_changed);
  }

  void _changed() {
    if (!_active) {
      _cancel?.cancel();
      if (mounted) setState(() {});
    }
  }

  Future<void> _save() async {
    if (!_active || _saving) return;
    setState(() => _saving = true);
    final cancel = _cancel = CancelToken();
    try {
      final video = _video;
      if (video) {
        await _saver.saveVideo(_url, cancel: cancel, isActive: () => _active);
      } else {
        await _saver.save(_url, cancel: cancel, isActive: () => _active);
      }
      if (mounted && _active) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Color(0xFF258B56),
            content: Text(
              video ? 'Video Saved to Gallery' : 'Image Saved to Gallery',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted && _active) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is PlatformException && error.code == 'permission_denied'
                  ? 'Allow adding photos in Settings to save this image.'
                  : 'Unable to save image. Check your connection and available storage, then try again.',
            ),
            action:
                error is PlatformException && error.code == 'permission_denied'
                ? SnackBarAction(
                    label: 'Open Settings',
                    onPressed: () {
                      const ChatDeviceMedia().openSettings().catchError(
                        (Object _) {},
                      );
                    },
                  )
                : null,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _preferences.removeListener(_changed);
    _cancel?.cancel();
    _pages.dispose();
    _thumbnails.dispose();
    if (widget.saver == null) _saver.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: SafeArea(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            top: 68,
            bottom: _media.length > 1 ? 96 : 0,
            child: !_active
                ? const Center(child: Text('Sign in again to view this image.'))
                : PageView.builder(
                    controller: _pages,
                    itemCount: _media.length,
                    onPageChanged: _select,
                    itemBuilder: (context, index) {
                      final item = _media[index];
                      if (item.kind == ChatMessageKind.video) {
                        return Center(
                          child: index == _index
                              ? ChatVideoMessage(
                                  url: item.mediaUrl,
                                  width: MediaQuery.sizeOf(context).width,
                                  maxHeight:
                                      (MediaQuery.sizeOf(context).height -
                                              MediaQuery.paddingOf(
                                                context,
                                              ).vertical -
                                              180)
                                          .clamp(60.0, double.infinity),
                                )
                              : const SizedBox(),
                        );
                      }
                      return InteractiveViewer(
                        minScale: .5,
                        maxScale: 5,
                        child: Center(
                          child: Image.network(
                            item.mediaUrl!.toString(),
                            fit: BoxFit.contain,
                            loadingBuilder: (_, child, progress) =>
                                progress == null
                                ? child
                                : const AppActivityIndicator(),
                            errorBuilder: (_, _, _) =>
                                const Text('Image unavailable'),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const Positioned(
            top: 22,
            left: 72,
            right: 72,
            child: Text(
              'Media',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (_active && _media.length > 1)
            Positioned(
              bottom: 12,
              left: 16,
              right: 16,
              child: SizedBox(
                height: 64,
                child: ListView.separated(
                  controller: _thumbnails,
                  scrollDirection: Axis.horizontal,
                  itemCount: _media.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) => InkWell(
                    key: ValueKey('media-thumbnail-$index'),
                    onTap: () => _pages.animateToPage(
                      index,
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                    ),
                    child: Container(
                      width: 56,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _index == index
                              ? DarkColors.primaryColor
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child:
                            _media[index].kind == ChatMessageKind.video &&
                                _media[index].thumbnailUrl == null
                            ? const ColoredBox(
                                color: Color(0xFF232323),
                                child: Icon(
                                  Icons.play_arrow,
                                  color: Colors.white,
                                ),
                              )
                            : Image.network(
                                (_media[index].thumbnailUrl ??
                                        _media[index].mediaUrl!)
                                    .toString(),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const Icon(
                                  Icons.image_not_supported_outlined,
                                  color: Colors.white54,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(top: 12, left: 16, child: BackButtonWidget()),
          Positioned(
            top: 12,
            right: 16,
            child: IconButton.filled(
              tooltip: _video
                  ? 'Save video to gallery'
                  : 'Save image to gallery',
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xCC202020),
                minimumSize: const Size.square(44),
              ),
              onPressed: _active && !_saving ? _save : null,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: AppActivityIndicator(),
                    )
                  : const Icon(Icons.download_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    ),
  );
}
