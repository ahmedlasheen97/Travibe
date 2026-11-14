import 'dart:typed_data';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/core/media/media_upload_model.dart';
import 'package:travibe/core/media/upload_diagnostics.dart';

enum MediaUploadStage { uploading, finalizing, processing }

/// Dedicated raw-byte transport; it must never inherit the API client's headers
/// or interceptors. Exposed for transport configuration/regression verification.
Dio createSignedStorageClient({HttpClientAdapter? adapter}) {
  final client = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  // clear() alone retains ImplyContentTypeInterceptor in Dio 5.11.
  client.interceptors.clear(keepImplyContentTypeInterceptor: false);
  if (adapter != null) client.httpClientAdapter = adapter;
  return client;
}

/// Time allowed to send [bytes] to storage. Dio's `sendTimeout` limits the
/// whole request body, so a fixed value fails large files on slow uplinks.
/// Assumes at least ~32 KB/s (≈256 kbit/s) plus 30s, between 60s and 10 min.
Duration storageSendTimeout(int bytes) =>
    Duration(seconds: (30 + bytes ~/ (32 * 1024)).clamp(60, 600));

/// Reusable upload pipeline. API and object-storage transports never share
/// interceptors, credentials or default JSON headers. No request logging.
class MediaUploadService {
  MediaUploadService({
    ApiService? api,
    HttpClientAdapter? storageAdapter,
    DateTime Function()? now,
    Future<void> Function(Duration)? wait,
    this.maxPolls = 15,
    this.pollInterval = const Duration(seconds: 2),
    this.allowedContentTypes = const {
      'image/jpeg',
      'image/png',
      'image/gif',
      'image/webp',
    },
  }) : _api = api ?? ApiService(observer: observeMediaApiRequest),
       _now = now ?? DateTime.now,
       _wait = wait ?? Future<void>.delayed,
       _storage = createSignedStorageClient(adapter: storageAdapter);
  final ApiService _api;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _wait;
  final int maxPolls;
  final Duration pollInterval;
  final Set<String> allowedContentTypes;
  String? _recoveryContentType;
  String get _expectedType =>
      (_recoveryContentType ?? 'image/jpeg').split('/').first;
  final Dio _storage;
  int? _recoveryMediaId;
  Uint8List? _recoveryBytes;
  bool _putConfirmed = false;

  void _clearRecovery() {
    _recoveryMediaId = null;
    _recoveryBytes = null;
    _putConfirmed = false;
    _recoveryContentType = null;
  }

  static ApiError _processingPending() => ApiError(
    message:
        'The existing photo upload has not finished processing. Your selected photo and edits are kept. Save again to check its status.',
  );

  /// No writes can be repeated while a previous outcome remains ambiguous.
  static ApiError _uncertain() => ApiError(
    message:
        'The upload result is uncertain. Your photo and edits are kept. Save again to check its status; do not upload it again until the server confirms the result.',
  );

  void close() => _storage.close(force: true);

  Future<int> upload({
    required String filename,
    required String contentType,
    required Uint8List bytes,
    required bool Function() isActive,
    required CancelToken cancelToken,
    required void Function(MediaUploadStage) onStage,
    void Function(int sent, int total)? onProgress,
  }) async {
    void checkActive() {
      if (!isActive() || cancelToken.isCancelled) {
        throw ApiError(message: 'Photo upload was cancelled.');
      }
    }

    var diagnosticStage = UploadDiagnosticStage.validation;
    final stageTimer = Stopwatch()..start();
    try {
      checkActive();
      if (filename.isEmpty ||
          filename.runes.length > 255 ||
          bytes.isEmpty ||
          !allowedContentTypes.contains(contentType)) {
        throw ApiError(
          message:
              'Choose a JPEG, PNG, GIF or WebP photo with a valid filename.',
        );
      }
      final limit = contentType.startsWith('video/')
          ? 100 * 1024 * 1024
          : 20 * 1024 * 1024;
      if (bytes.length > limit) {
        throw ApiError(message: 'The selected media is too large.');
      }
      if (_recoveryMediaId != null) {
        diagnosticStage = UploadDiagnosticStage.polling;
        stageTimer.reset();
        onStage(MediaUploadStage.processing);
        final existingId = _recoveryMediaId!;
        final samePhoto =
            identical(_recoveryBytes, bytes) ||
            listEquals(_recoveryBytes, bytes);
        final existing = UploadMedia.fromEnvelope(
          await _api
              .get('media/$existingId')
              .timeout(const Duration(seconds: 15)),
          expectedType: _expectedType,
        );
        checkActive();
        if (existing.id != existingId) {
          throw const FormatException('Unexpected media');
        }
        if (existing.status == MediaStatus.pending) {
          throw _putConfirmed ? _processingPending() : _uncertain();
        }
        if (existing.status == MediaStatus.processing) {
          _putConfirmed = true;
          if (!samePhoto) throw _processingPending();
          return await _poll(existingId, checkActive);
        }
        if (existing.status == MediaStatus.ready &&
            samePhoto &&
            _recoveryContentType == contentType) {
          _putConfirmed = true;
          return existingId;
        }
        // A definitive failed/ready result resolves the earlier write. A new
        // selection or failed media can now use a new authorization on this save.
        _clearRecovery();
      }
      onStage(MediaUploadStage.uploading);
      diagnosticStage = UploadDiagnosticStage.presign;
      stageTimer.reset();
      final signed = MediaPresign.fromJson(
        await _api
            .post('media/presign', {
              'filename': filename,
              'content_type': contentType,
              'size': bytes.length,
            })
            .timeout(const Duration(seconds: 30)),
      );
      checkActive();
      if (!signed.expiresAt.isAfter(_now().toUtc())) {
        throw ApiError(
          message: 'Photo upload authorization expired. Save again to retry.',
        );
      }
      diagnosticStage = UploadDiagnosticStage.storage;
      stageTimer.reset();
      final headers = <String, dynamic>{};
      final authority = Uri.parse(signed.uploadUrl).authority.toLowerCase();
      for (final entry in signed.uploadHeaders.entries) {
        if (entry.key.toLowerCase() == 'host') {
          // dart:io sets Host from the URL. It must match the signed authority;
          // never override it or turn an array into a bracketed string.
          if (entry.value.length != 1 ||
              entry.value.single.toLowerCase() != authority) {
            throw const FormatException('Invalid signed host');
          }
        } else {
          if (entry.key.toLowerCase() == 'content-type' &&
              (entry.value.length != 1 ||
                  entry.value.single.split(';').first.trim().toLowerCase() !=
                      contentType)) {
            throw const FormatException('Invalid signed content type');
          }
          if (entry.key.toLowerCase() == 'content-length' &&
              (entry.value.length != 1 ||
                  int.tryParse(entry.value.single) != bytes.length)) {
            throw const FormatException('Invalid signed length');
          }
          headers[entry.key] = entry.value.length == 1
              ? entry.value.single
              : entry.value;
        }
      }
      final storageTimer = Stopwatch()..start();
      try {
        final response = await _storage.request<String>(
          signed.uploadUrl,
          data: bytes,
          cancelToken: cancelToken,
          onSendProgress: onProgress,
          options: Options(
            method: signed.uploadMethod,
            sendTimeout: storageSendTimeout(bytes.length),
            headers: headers,
            responseType: ResponseType.plain,
            followRedirects: false,
            validateStatus: (status) =>
                status != null && status >= 200 && status < 300,
          ),
        );
        logUploadRequest(
          UploadDiagnosticStage.storage,
          response,
          null,
          storageTimer.elapsed,
        );
      } on DioException catch (error) {
        logUploadRequest(
          UploadDiagnosticStage.storage,
          error.response,
          error,
          storageTimer.elapsed,
        );
        // A receive timeout/connection loss may occur after all bytes arrived.
        // Never finalize or start another PUT to resolve that uncertainty.
        if ([
              DioExceptionType.receiveTimeout,
              DioExceptionType.sendTimeout,
              DioExceptionType.connectionError,
              DioExceptionType.unknown,
            ].contains(error.type) ||
            error.response?.statusCode == 408 ||
            (error.response?.statusCode != null &&
                error.response!.statusCode! >= 500)) {
          _recoveryMediaId = signed.media.id;
          _recoveryContentType = contentType;
          _recoveryBytes = bytes;
          _putConfirmed = false;
          throw _uncertain();
        }
        rethrow;
      }
      // A confirmed PUT permits one finalize. Any later ambiguous result is
      // reconciled with read-only status requests rather than repeating writes.
      _recoveryMediaId = signed.media.id;
      _recoveryContentType = contentType;
      _recoveryBytes = bytes;
      _putConfirmed = true;
      checkActive();
      diagnosticStage = UploadDiagnosticStage.finalize;
      stageTimer.reset();
      onStage(MediaUploadStage.finalizing);
      dynamic finalizeResponse;
      var alreadyFinalized = false;
      try {
        finalizeResponse = await _api
            .post('media/${signed.media.id}/finalize', {})
            .timeout(const Duration(seconds: 30));
      } on ApiError catch (error) {
        checkActive();
        if (error.statusCode == 409) {
          // The write may have already succeeded. Status GET, never another
          // finalize or PUT, establishes whether this record is usable.
          alreadyFinalized = true;
        } else if (error.statusCode == 422) {
          // The documented validation/missing-object failure is definitive.
          // Preserve the API validation error and allow an explicit new upload.
          _clearRecovery();
          rethrow;
        } else {
          rethrow;
        }
      }
      checkActive();
      if (!alreadyFinalized) {
        final finalized = UploadMedia.fromFinalizeEnvelope(
          finalizeResponse,
          expectedType: _expectedType,
        );
        if (finalized.id != signed.media.id) {
          throw const FormatException('Unexpected media');
        }
        if (finalized.status == MediaStatus.failed) {
          _clearRecovery();
          throw ApiError(
            message: 'The photo could not be processed. Save again to retry.',
          );
        }
      }
      diagnosticStage = UploadDiagnosticStage.polling;
      stageTimer.reset();
      onStage(MediaUploadStage.processing);
      // GET is authoritative even if finalize reports ready.
      return await _poll(signed.media.id, checkActive);
    } catch (error) {
      logUploadFailure(diagnosticStage, error, elapsed: stageTimer.elapsed);
      // Do not expose signed URLs, storage error bodies, headers or raw errors.
      if (error is FormatException) {
        throw ApiError(
          message:
              'The server returned an unexpected upload response. Your photo and edits are kept. Save again to check the existing media status.',
        );
      }
      if (error is ApiError) rethrow;
      if (_recoveryMediaId != null) {
        if (!_putConfirmed) throw _uncertain();
        throw ApiError(
          message:
              'The photo bytes were uploaded, but processing could not be confirmed. Your photo and edits are kept. Save again to check the existing media status.',
        );
      }
      throw ApiError(
        message: 'Unable to upload your photo. Save again to retry.',
      );
    }
  }

  Future<int> _poll(int id, void Function() checkActive) async {
    for (var attempt = 0; attempt < maxPolls; attempt++) {
      checkActive();
      final media = UploadMedia.fromEnvelope(
        await _api.get('media/$id').timeout(const Duration(seconds: 15)),
        expectedType: _expectedType,
      );
      checkActive();
      if (media.id != id) throw const FormatException('Unexpected media');
      if (media.status == MediaStatus.ready) {
        _putConfirmed = true;
        return media.id;
      }
      if (media.status == MediaStatus.failed) {
        _clearRecovery();
        throw ApiError(
          message: 'The photo could not be processed. Save again to retry.',
        );
      }
      if (attempt + 1 < maxPolls) await _wait(pollInterval);
    }
    throw _processingPending();
  }
}
