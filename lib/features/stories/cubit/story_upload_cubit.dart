import 'dart:async';
import 'dart:collection';
import 'dart:ui' show Size;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/media/media_upload_service.dart';
import 'package:travibe/features/create_post/cubit/post_upload_cubit.dart'
    show MediaUploadFactory;
import 'package:travibe/features/stories/cubit/story_publish_cubit.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/widgets/story_image_exporter.dart';

/// What the editor hands over when Post is tapped; the editor then closes.
class StoryUploadJob {
  const StoryUploadJob({required this.draft, this.viewport});
  final StoryEditorDraft draft;

  /// Editor canvas size, so the export matches what the user saw.
  final Size? viewport;
}

sealed class StoryUploadState {
  const StoryUploadState();
}

class StoryUploadIdle extends StoryUploadState {
  const StoryUploadIdle();
}

class StoryUploading extends StoryUploadState {
  const StoryUploading({required this.progress, this.queued = 0});

  /// 0..1 across preparing, uploading, processing and publishing.
  final double progress;
  final int queued;
}

class StoryUploadFailed extends StoryUploadState {
  const StoryUploadFailed({required this.message, this.queued = 0});
  final String message;
  final int queued;
}

class StoryUploadDone extends StoryUploadState {
  const StoryUploadDone(this.story);
  final StoryDetail? story;
}

typedef StoryPublisherFactory = StoryPublishCubit Function();

/// Publishes Stories in the background (like posts) so the editor can close
/// on Post. One Story at a time; a failed Story blocks the queue until it is
/// retried or discarded. Each Story keeps its own publisher, so a retry
/// reuses the exported photo and upload and never creates a duplicate.
class StoryUploadCubit extends Cubit<StoryUploadState> {
  StoryUploadCubit({
    StoriesRepo? repo,
    MediaUploadFactory? uploads,
    StoryImageExporter? exporter,
    PreferencesManager? preferences,
    StoryPublisherFactory? publisher,
  }) : _preferences = preferences ?? PreferencesManager(),
       super(const StoryUploadIdle()) {
    final storiesRepo = repo ?? StoriesRepo();
    _newPublisher =
        publisher ??
        () => StoryPublishCubit(
          repo: storiesRepo,
          uploads: (uploads ?? MediaUploadService.new)(),
          exporter: exporter,
          session: _preferences,
        );
    _session = _preferences.sessionRevision;
    _preferences.addListener(_sessionChanged);
  }

  final PreferencesManager _preferences;
  late final StoryPublisherFactory _newPublisher;
  final _queue = Queue<StoryUploadJob>();
  late int _session;

  StoryUploadJob? _job;
  StoryPublishCubit? _publisher;
  StreamSubscription<StoryPublishState>? _subscription;

  static const failureMessage = 'Couldn’t publish your story';

  int get pending => _queue.length + (_job == null ? 0 : 1);

  void enqueue(StoryUploadJob job) {
    if (isClosed) return;
    _queue.add(job);
    final state = this.state;
    if (state is StoryUploading) {
      emit(StoryUploading(progress: state.progress, queued: _queue.length));
    }
    if (_job == null) _next();
  }

  /// Runs the failed Story again; the publisher verifies before re-posting.
  void retry() {
    final publisher = _publisher;
    final job = _job;
    if (isClosed ||
        state is! StoryUploadFailed ||
        publisher == null ||
        job == null) {
      return;
    }
    emit(StoryUploading(progress: 0, queued: _queue.length));
    unawaited(publisher.publish(job.draft, viewport: job.viewport));
  }

  void discard() {
    if (isClosed || state is! StoryUploadFailed) return;
    _finishJob();
    emit(const StoryUploadIdle());
    _next();
  }

  void _next() {
    if (isClosed || _job != null || _queue.isEmpty) return;
    final job = _job = _queue.removeFirst();
    final publisher = _publisher = _newPublisher();
    _subscription = publisher.stream.listen((value) => _onPublish(value));
    emit(StoryUploading(progress: 0, queued: _queue.length));
    unawaited(publisher.publish(job.draft, viewport: job.viewport));
  }

  void _onPublish(StoryPublishState value) {
    if (isClosed) return;
    if (value.busy) {
      emit(StoryUploading(progress: value.fraction, queued: _queue.length));
    } else if (value.sessionEnded) {
      _reset();
      emit(const StoryUploadIdle());
    } else if (value.status == StoryPublishStatus.failure) {
      emit(StoryUploadFailed(message: failureMessage, queued: _queue.length));
    } else if (value.status == StoryPublishStatus.success) {
      _finishJob();
      emit(StoryUploadDone(value.story));
      _next();
    }
  }

  void _finishJob() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_publisher?.close());
    _publisher = null;
    _job = null;
  }

  void _reset() {
    _queue.clear();
    _finishJob();
  }

  void _sessionChanged() {
    if (isClosed || _preferences.sessionRevision == _session) return;
    _session = _preferences.sessionRevision;
    _reset();
    emit(const StoryUploadIdle());
  }

  @override
  Future<void> close() {
    _preferences.removeListener(_sessionChanged);
    _reset();
    return super.close();
  }
}
