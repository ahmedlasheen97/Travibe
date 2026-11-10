import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/media/media_upload_service.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';
import 'package:travibe/features/stories/data/story_elements.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';

enum StoryPublishStatus {
  idle,
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
  });
  final StoryPublishStatus status;
  final ApiError? error;
  final StoryDetail? story;
  final bool uncertain, sessionEnded;
  bool get busy =>
      status == StoryPublishStatus.uploading ||
      status == StoryPublishStatus.processing ||
      status == StoryPublishStatus.publishing;
  String get progress => switch (status) {
    StoryPublishStatus.uploading => 'Uploading photo…',
    StoryPublishStatus.processing => 'Processing photo…',
    StoryPublishStatus.publishing => 'Publishing Story…',
    _ => '',
  };
}

class StoryPublishCubit extends Cubit<StoryPublishState> {
  StoryPublishCubit({
    StoriesRepo? repo,
    MediaUploadService? uploads,
    PreferencesManager? session,
    this.onPublished,
  }) : repo = repo ?? StoriesRepo(),
       uploads = uploads ?? MediaUploadService(),
       _ownsUploads = uploads == null,
       session = session ?? PreferencesManager(),
       super(const StoryPublishState()) {
    _sessionRevision = this.session.sessionRevision;
    this.session.addListener(_sessionChanged);
  }
  final StoriesRepo repo;
  final MediaUploadService uploads;
  final PreferencesManager session;
  final Future<void> Function()? onPublished;
  final bool _ownsUploads;
  late final int _sessionRevision;
  CancelToken? _cancel;
  bool _confirmed = false;
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
          message: 'Your session changed. Reopen the Story editor to publish.',
        ),
      ),
    );
  }

  Future<void> publish(StoryEditorDraft draft) async {
    if (isClosed ||
        _confirmed ||
        state.busy ||
        state.uncertain ||
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
    final mime = draft.image.contentType;
    if (mime == null) {
      emit(
        StoryPublishState(
          status: StoryPublishStatus.failure,
          error: ApiError(
            message:
                'Choose a JPEG, PNG, GIF or WebP photo. The original format is not supported.',
          ),
        ),
      );
      return;
    }
    _cancel = CancelToken();
    emit(const StoryPublishState(status: StoryPublishStatus.uploading));
    try {
      // The shared service rechecks ready IDs on retry, never repeating an
      // ambiguous PUT. The photo remains original, with no flattened overlays.
      final mediaId = await uploads.upload(
        filename: draft.image.name,
        contentType: mime,
        bytes: draft.image.bytes,
        isActive: _active,
        cancelToken: _cancel!,
        onStage: (stage) {
          if (!_active()) return;
          emit(
            StoryPublishState(
              status: stage == MediaUploadStage.uploading
                  ? StoryPublishStatus.uploading
                  : StoryPublishStatus.processing,
            ),
          );
        },
      );
      if (!_active()) return;
      emit(const StoryPublishState(status: StoryPublishStatus.publishing));
      final story = await repo.create(
        CreateStoryRequest(mediaId: mediaId, draft: draft),
        cancelToken: _cancel,
      );
      if (!_active()) return;
      // Creation is confirmed even if refreshing Home later fails. Never turn a
      // successful POST into a retryable failure and accidentally create twice.
      _confirmed = true;
      try {
        await onPublished?.call();
      } catch (_) {
        /* Home retains its retry state. */
      }
      if (_active()) {
        emit(
          StoryPublishState(status: StoryPublishStatus.success, story: story),
        );
      }
    } catch (error) {
      if (!_active()) return;
      emit(
        StoryPublishState(
          status: StoryPublishStatus.failure,
          uncertain: error is StoryCreationUncertain,
          error: error is ApiError
              ? error
              : ApiError(
                  message: 'Unable to publish your Story. Your edits are kept.',
                ),
        ),
      );
    }
  }

  @override
  Future<void> close() {
    session.removeListener(_sessionChanged);
    _cancel?.cancel();
    if (_ownsUploads) uploads.close();
    return super.close();
  }
}
