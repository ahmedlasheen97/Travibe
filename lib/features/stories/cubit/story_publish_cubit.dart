import 'dart:async';
import 'dart:ui' show Size;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/media/media_upload_service.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';
import 'package:travibe/features/stories/data/story_elements.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';
import 'package:travibe/features/stories/widgets/story_image_exporter.dart';

enum StoryPublishStatus {
  idle,
  preparing,
  uploading,
  processing,
  publishing,
  success,
  failure,
}

class StoryPublishState {
  const StoryPublishState({
    this.status = StoryPublishStatus.idle,
    this.error,
    this.story,
    this.uncertain = false,
    this.sessionEnded = false,
    this.fraction = 0,
  });
  final StoryPublishStatus status;
  final ApiError? error;
  final StoryDetail? story;

  /// The last attempt may have created the Story. A retry checks first.
  final bool uncertain;
  final bool sessionEnded;

  /// 0..1 across preparing, uploading, processing and publishing.
  final double fraction;
  bool get busy =>
      status == StoryPublishStatus.preparing ||
      status == StoryPublishStatus.uploading ||
      status == StoryPublishStatus.processing ||
      status == StoryPublishStatus.publishing;
  String get progress => switch (status) {
    StoryPublishStatus.preparing => 'Preparing photo…',
    StoryPublishStatus.uploading => 'Uploading photo…',
    StoryPublishStatus.processing => 'Processing photo…',
    StoryPublishStatus.publishing => 'Publishing Story…',
    _ => '',
  };
}

/// Exports, uploads and creates one Story. Calling [publish] again after a
/// failure retries without duplicates: the exported JPEG is reused, the media
/// service resumes (never repeats an ambiguous PUT), and an uncertain creation
/// is verified read-only before any new POST.
class StoryPublishCubit extends Cubit<StoryPublishState> {
  StoryPublishCubit({
    StoriesRepo? repo,
    MediaUploadService? uploads,
    PreferencesManager? session,
    StoryImageExporter? exporter,
    this.onPublished,
  }) : repo = repo ?? StoriesRepo(),
       exporter = exporter ?? const StoryImageExporter(),
       uploads = uploads ?? MediaUploadService(),
       _ownsUploads = uploads == null,
       session = session ?? PreferencesManager(),
       super(const StoryPublishState()) {
    _sessionRevision = this.session.sessionRevision;
    this.session.addListener(_sessionChanged);
  }
  final StoriesRepo repo;
  final MediaUploadService uploads;
  final StoryImageExporter exporter;
  final PreferencesManager session;
  final Future<void> Function()? onPublished;
  final bool _ownsUploads;
  late final int _sessionRevision;
  CancelToken? _cancel;
  bool _confirmed = false;

  // Retry state for the same draft.
  StoryEditorDraft? _exportedDraft;
  StoryExportedImage? _export;
  int? _unverifiedMediaId;

  static const failureMessage =
      'Couldn’t publish your story. Check your connection and try again.';

  bool _active() =>
      !isClosed &&
      !state.sessionEnded &&
      session.sessionRevision == _sessionRevision &&
      session.hasSession;

  void _sessionChanged() {
    if (isClosed || session.sessionRevision == _sessionRevision) return;
    _cancel?.cancel();
    emit(
      StoryPublishState(
        sessionEnded: true,
        status: StoryPublishStatus.failure,
        error: ApiError(
          message: 'You signed out, so your story wasn’t posted.',
        ),
      ),
    );
  }

  void _progress(StoryPublishStatus status, double fraction) {
    if (_active()) {
      emit(
        StoryPublishState(
          status: status,
          fraction: fraction.clamp(0.0, 1.0),
          uncertain: _unverifiedMediaId != null,
        ),
      );
    }
  }

  void _fail(Object error) {
    if (!_active()) return;
    // Server validation (e.g. the active-story limit) is written for users;
    // transport and ambiguity details are not.
    final message = error is ApiError && error.statusCode == 422
        ? error.message
        : failureMessage;
    emit(
      StoryPublishState(
        status: StoryPublishStatus.failure,
        uncertain: _unverifiedMediaId != null,
        error: ApiError(message: message, statusCode: _statusOf(error)),
      ),
    );
  }

  static int? _statusOf(Object error) =>
      error is ApiError ? error.statusCode : null;

  Future<void> _succeed(StoryDetail? story) async {
    // Creation is confirmed even if refreshing Home later fails. Never turn a
    // successful POST into a retryable failure and accidentally create twice.
    _confirmed = true;
    _unverifiedMediaId = null;
    try {
      await onPublished?.call();
    } catch (_) {
      /* Home retains its retry state. */
    }
    if (_active()) {
      emit(
        StoryPublishState(
          status: StoryPublishStatus.success,
          story: story,
          fraction: 1,
        ),
      );
    }
  }

  /// [viewport] is the editor canvas size the photo is cropped to.
  Future<void> publish(StoryEditorDraft draft, {Size? viewport}) async {
    if (isClosed ||
        _confirmed ||
        state.busy ||
        state.sessionEnded ||
        state.status == StoryPublishStatus.success) {
      return;
    }
    if (!_active()) {
      emit(
        StoryPublishState(
          status: StoryPublishStatus.failure,
          error: ApiError(
            message: 'Sign in with a verified email to publish a Story.',
          ),
        ),
      );
      return;
    }
    try {
      StoryElements.encode(draft.layers);
    } on FormatException catch (e) {
      emit(
        StoryPublishState(
          status: StoryPublishStatus.failure,
          error: ApiError(message: e.message),
        ),
      );
      return;
    }
    final cancel = _cancel = CancelToken();
    try {
      // 1. An earlier POST may have succeeded: check before writing again.
      final unverified = _unverifiedMediaId;
      if (unverified != null) {
        _progress(StoryPublishStatus.publishing, .95);
        final existing = await repo.findStoryByMedia(unverified);
        if (!_active()) return;
        if (existing != null) return await _succeed(existing);
        // Not created: the media is still unclaimed, so POST it again.
        // The API rejects already-attached media, so this cannot duplicate.
        try {
          return await _create(draft, unverified, cancel);
        } on ApiError catch (error) {
          // A late first POST may have claimed the media in the meantime.
          if (error.statusCode != 422 || !_active()) rethrow;
          final late = await repo.findStoryByMedia(unverified);
          if (!_active()) return;
          if (late != null) return await _succeed(late);
          rethrow;
        }
      }

      // 2. Export once per draft; a retry reuses the same bytes so the media
      // service can resume the earlier upload instead of sending it again.
      var export = identical(_exportedDraft, draft) ? _export : null;
      if (export == null) {
        _progress(StoryPublishStatus.preparing, 0);
        final timer = Stopwatch()..start();
        export = await exporter.export(draft, viewport);
        _log(
          'export ${timer.elapsedMilliseconds}ms ${export.width}x'
          '${export.height} ${export.contentType} '
          '${(export.bytes.length / 1048576).toStringAsFixed(2)}MB '
          '(picked photo ${draft.image.width}x${draft.image.height} '
          '${(draft.image.bytes.length / 1048576).toStringAsFixed(2)}MB)',
        );
        if (!_active()) return;
        _exportedDraft = draft;
        _export = export;
      }

      // 3. Upload (0.1–0.85), then wait for processing (0.85–0.95).
      _progress(StoryPublishStatus.uploading, .1);
      final timer = Stopwatch()..start();
      final mediaId = await uploads.upload(
        filename: export.filename,
        contentType: export.contentType,
        bytes: export.bytes,
        isActive: _active,
        cancelToken: cancel,
        onStage: (stage) => _progress(
          stage == MediaUploadStage.uploading
              ? StoryPublishStatus.uploading
              : StoryPublishStatus.processing,
          stage == MediaUploadStage.uploading ? .1 : .85,
        ),
        onProgress: (sent, total) {
          if (total > 0) {
            _progress(StoryPublishStatus.uploading, .1 + .75 * sent / total);
          }
        },
      );
      _log(
        'upload ${timer.elapsedMilliseconds}ms '
        '${(export.bytes.length / 1048576).toStringAsFixed(2)}MB sent',
      );
      if (!_active()) return;
      await _create(draft, mediaId, cancel);
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> _create(
    StoryEditorDraft draft,
    int mediaId,
    CancelToken cancel,
  ) async {
    _progress(StoryPublishStatus.publishing, .95);
    try {
      final story = await repo.create(
        CreateStoryRequest(mediaId: mediaId, draft: draft),
        cancelToken: cancel,
      );
      if (!_active()) return;
      await _succeed(story);
    } on StoryCreationUncertain {
      if (!_active()) return;
      _unverifiedMediaId = mediaId;
      // Check right away; if the Story exists, this was a success after all.
      StoryDetail? existing;
      try {
        existing = await repo.findStoryByMedia(mediaId);
      } catch (_) {
        existing = null; // Still unknown: Retry checks again before posting.
      }
      if (!_active()) return;
      if (existing != null) return await _succeed(existing);
      rethrow;
    }
  }

  static void _log(String message) {
    if (kDebugMode) debugPrint('[story-publish] $message');
  }

  @override
  Future<void> close() {
    session.removeListener(_sessionChanged);
    _cancel?.cancel();
    if (_ownsUploads) uploads.close();
    return super.close();
  }
}
