import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'chat_device_media.dart';

class ChatImageSaver {
  ChatImageSaver({Dio? dio, ChatDeviceMedia? device})
    : _dio = dio ?? Dio(),
      _device = device ?? const ChatDeviceMedia();
  final Dio _dio;
  final ChatDeviceMedia _device;
  Future<void> save(
    Uri url, {
    required CancelToken cancel,
    required bool Function() isActive,
  }) async {
    if (!isActive() || cancel.isCancelled) {
      throw const FormatException('Session changed.');
    }
    if (url.scheme != 'https' || url.host.isEmpty || url.userInfo.isNotEmpty) {
      throw const FormatException('Invalid image URL.');
    }
    final response = await _dio
        .get<ResponseBody>(
          url.toString(),
          cancelToken: cancel,
          options: Options(
            responseType: ResponseType.stream,
            followRedirects: false,
            sendTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 20),
          ),
        )
        .timeout(
          const Duration(seconds: 25),
          onTimeout: () {
            cancel.cancel();
            throw TimeoutException('Image download timed out.');
          },
        );
    if (response.statusCode != 200 || response.data == null) {
      throw const FormatException('Image download failed.');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.data!.stream.timeout(
      const Duration(seconds: 20),
    )) {
      if (!isActive() || cancel.isCancelled) {
        throw const FormatException('Session changed.');
      }
      if (bytes.length + chunk.length > 20 * 1024 * 1024) {
        cancel.cancel();
        throw const FormatException('Image is too large.');
      }
      bytes.add(chunk);
    }
    final image = bytes.takeBytes();
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(image);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width <= 0 ||
          descriptor.height <= 0 ||
          descriptor.width * descriptor.height > 100000000) {
        throw const FormatException('Invalid image.');
      }
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
    if (!isActive() || cancel.isCancelled) {
      throw const FormatException('Session changed.');
    }
    await _device.saveImage(image);
  }

  /// Stream large videos to an app-temporary file; never bridge 100 MB in RAM.
  Future<void> saveVideo(
    Uri url, {
    required CancelToken cancel,
    required bool Function() isActive,
  }) async {
    if (!isActive() ||
        cancel.isCancelled ||
        url.scheme != 'https' ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty) {
      throw const FormatException('Invalid media request.');
    }
    final directory = await Directory.systemTemp.createTemp('travibe-gallery-');
    try {
      final response = await _dio
          .get<ResponseBody>(
            url.toString(),
            cancelToken: cancel,
            options: Options(
              responseType: ResponseType.stream,
              followRedirects: false,
              receiveTimeout: const Duration(seconds: 20),
            ),
          )
          .timeout(
            const Duration(seconds: 25),
            onTimeout: () {
              cancel.cancel();
              throw TimeoutException('Video download timed out.');
            },
          );
      final mime = response.headers
          .value(Headers.contentTypeHeader)
          ?.split(';')
          .first
          .trim();
      final extension = switch (mime) {
        'video/mp4' => 'mp4',
        'video/quicktime' => 'mov',
        'video/webm' => 'webm',
        _ => null,
      };
      if (response.statusCode != 200 ||
          response.data == null ||
          extension == null) {
        throw const FormatException('Unsupported video.');
      }
      final file = File('${directory.path}/video.$extension');
      final sink = file.openWrite();
      var size = 0;
      try {
        await for (final chunk in response.data!.stream.timeout(
          const Duration(seconds: 20),
        )) {
          if (!isActive() || cancel.isCancelled) {
            throw const FormatException('Session changed.');
          }
          size += chunk.length;
          if (size > 100 * 1024 * 1024) {
            cancel.cancel();
            throw const FormatException('Video is too large.');
          }
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (size < 16 || !isActive() || cancel.isCancelled) {
        throw const FormatException('Invalid video.');
      }
      await _device.saveVideo(file.path, mime!);
    } finally {
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }

  void dispose() => _dio.close(force: true);
}
