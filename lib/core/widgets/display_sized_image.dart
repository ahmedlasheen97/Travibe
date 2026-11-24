import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Decodes [imageProvider] at the size it is drawn with `BoxFit.cover`
/// instead of its full resolution (uploads are up to 2048 px, while a feed
/// card is ~350×220 pt). That keeps decode, GPU upload and image-cache memory
/// proportional to the screen, so scrolling a feed doesn't stall on photos.
///
/// Unlike [ResizeImage] with a single dimension, the target is the smallest
/// size that still *covers* [width]×[height] physical pixels for the image's
/// own aspect ratio, so cropping never upscales. Images already smaller than
/// that are decoded as they are.
@immutable
class DisplaySizedImage extends ImageProvider<DisplaySizedImageKey> {
  const DisplaySizedImage(
    this.imageProvider, {
    required this.width,
    required this.height,
  }) : assert(width > 0 && height > 0);

  /// The original provider (e.g. a [NetworkImage]).
  final ImageProvider imageProvider;

  /// Physical pixels the image must cover.
  final int width, height;

  /// [provider] sized for a [logicalWidth]×[logicalHeight] box on this
  /// screen (× device pixel ratio). Returns [provider] unchanged when the box
  /// isn't a finite, positive size.
  static ImageProvider of(
    BuildContext context,
    ImageProvider provider, {
    required double logicalWidth,
    required double logicalHeight,
  }) {
    if (!logicalWidth.isFinite ||
        !logicalHeight.isFinite ||
        logicalWidth <= 0 ||
        logicalHeight <= 0) {
      return provider;
    }
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    return DisplaySizedImage(
      provider,
      width: (logicalWidth * ratio).ceil(),
      height: (logicalHeight * ratio).ceil(),
    );
  }

  /// The decode size for an [intrinsicWidth]×[intrinsicHeight] image.
  @visibleForTesting
  static ui.TargetImageSize targetSize(
    int intrinsicWidth,
    int intrinsicHeight,
    int width,
    int height,
  ) {
    final scale = [
      width / intrinsicWidth,
      height / intrinsicHeight,
    ].reduce((a, b) => a > b ? a : b);
    if (scale >= 1) return const ui.TargetImageSize();
    return ui.TargetImageSize(
      width: (intrinsicWidth * scale).ceil(),
      height: (intrinsicHeight * scale).ceil(),
    );
  }

  @override
  Future<DisplaySizedImageKey> obtainKey(ImageConfiguration configuration) {
    Completer<DisplaySizedImageKey>? completer;
    SynchronousFuture<DisplaySizedImageKey>? result;
    imageProvider
        .obtainKey(configuration)
        .then(
          (key) {
            final sized = DisplaySizedImageKey._(key, width, height);
            if (completer == null) {
              result = SynchronousFuture(sized);
            } else {
              completer!.complete(sized);
            }
          },
          onError: (Object error, StackTrace stack) {
            completer ??= Completer<DisplaySizedImageKey>();
            completer!.completeError(error, stack);
          },
        );
    if (result != null) return result!;
    return (completer ??= Completer<DisplaySizedImageKey>()).future;
  }

  @override
  ImageStreamCompleter loadImage(
    DisplaySizedImageKey key,
    ImageDecoderCallback decode,
  ) {
    Future<ui.Codec> sized(
      ui.ImmutableBuffer buffer, {
      ui.TargetImageSizeCallback? getTargetSize,
    }) => decode(
      buffer,
      getTargetSize: (w, h) => targetSize(w, h, width, height),
    );
    return imageProvider.loadImage(key._providerKey, sized);
  }

  @override
  bool operator ==(Object other) =>
      other is DisplaySizedImage &&
      other.imageProvider == imageProvider &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(imageProvider, width, height);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'DisplaySizedImage')}'
      '($imageProvider, ${width}x$height)';
}

/// Cache key: the original key plus the decode size, so each size of the same
/// image is cached separately from the full-size one.
@immutable
class DisplaySizedImageKey {
  const DisplaySizedImageKey._(this._providerKey, this._width, this._height);
  final Object _providerKey;
  final int _width, _height;

  @override
  bool operator ==(Object other) =>
      other is DisplaySizedImageKey &&
      other._providerKey == _providerKey &&
      other._width == _width &&
      other._height == _height;

  @override
  int get hashCode => Object.hash(_providerKey, _width, _height);
}
