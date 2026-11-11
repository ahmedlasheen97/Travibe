import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/media/media_upload_service.dart';
import 'package:travibe/features/create_post/data/create_post_repo.dart';
import 'package:travibe/features/create_post/data/create_post_request.dart';
import 'package:travibe/features/home/data/post_model.dart';

part 'post_upload_state.dart';

typedef MediaUploadFactory = MediaUploadService Function();

/// Publishes composed posts in the background so the composer can close
/// immediately. Drafts run one at a time; a failed draft is kept for retry
/// with its already-uploaded photos, and is never dropped silently.
class PostUploadCubit extends Cubit<PostUploadState> {
  PostUploadCubit({
    CreatePostRepo? repo,
    MediaUploadFactory? uploads,
    PreferencesManager? preferences,
  }) : _repo = repo ?? CreatePostRepo(),
       _uploads = uploads ?? MediaUploadService.new,
       _preferences = preferences ?? PreferencesManager(),
       super(const PostUploadIdle()) {
    _session = _preferences.sessionRevision;
    _preferences.addListener(_sessionChanged);
  }

  final CreatePostRepo _repo;
  final MediaUploadFactory _uploads;
  final PreferencesManager _preferences;
  final _queue = Queue<CreatePostRequest>();

  /// One service per photo: each instance keeps that photo's recovery state,
  /// so a retry resumes (polls) instead of uploading the bytes again.
  final _services = <String, MediaUploadService>{};
  late int _session;
  int _generation = 0;
  CancelToken? _cancel;
  CreatePostRequest? _current;

  static const _failureMessage = 'Couldn’t upload your post.';

  int get pending => _queue.length + (_current == null ? 0 : 1);

  void enqueue(CreatePostRequest draft) {
    if (isClosed || draft.validationError != null) return;
    _queue.add(draft);
    final state = this.state;
    if (state is PostUploading) {
      emit(PostUploading(progress: state.progress, queued: _queue.length));
    }
    // A failed draft blocks the queue until it is retried or discarded.
    if (_current == null && state is! PostUploadFailed) unawaited(_next());
  }

  Future<void> retry() async {
    final state = this.state;
    if (isClosed || state is! PostUploadFailed || _current != null) return;
    _queue.addFirst(state.draft);
    await _next();
  }

  void discard() {
    final state = this.state;
    if (isClosed || state is! PostUploadFailed) return;
    _closeServices(state.draft);
    emit(const PostUploadIdle());
    if (_queue.isNotEmpty) unawaited(_next());
  }

  Future<void> _next() async {
    if (isClosed || _current != null || _queue.isEmpty) return;
    var draft = _queue.removeFirst();
    _current = draft;
    final generation = ++_generation;
    final cancel = _cancel = CancelToken();
    bool active() =>
        !isClosed && generation == _generation && !cancel.isCancelled;

    final units = draft.images.length + 1;
    void progress(int done, double fraction) {
      if (!active()) return;
      final value = ((done + fraction.clamp(0.0, 1.0)) / units).clamp(0.0, 1.0);
      emit(PostUploading(progress: value, queued: _queue.length));
    }

    progress(0, 0);
    try {
      for (var i = 0; i < draft.images.length; i++) {
        final image = draft.images[i];
        if (image.mediaId != null) {
          progress(i + 1, 0);
          continue;
        }
        final service = _services.putIfAbsent(image.localId, _uploads);
        final id = await service.upload(
          filename: image.filename,
          contentType: image.contentType,
          bytes: image.bytes,
          isActive: active,
          cancelToken: cancel,
          onStage: (stage) {
            if (stage != MediaUploadStage.uploading) progress(i, 0.9);
          },
          onProgress: (sent, total) {
            if (total > 0) progress(i, 0.8 * sent / total);
          },
        );
        if (!active()) return;
        final images = [...draft.images];
        images[i] = image.withMediaId(id);
        draft = draft.copyWith(images: images);
        _current = draft;
        progress(i + 1, 0);
      }
      final post = await _repo.create(draft);
      if (!active()) return;
      _closeServices(draft);
      _current = null;
      emit(PostUploadDone(post));
    } catch (error) {
      if (!active()) return;
      _current = null;
      emit(
        PostUploadFailed(
          draft: draft,
          queued: _queue.length,
          message: error is ApiError && error.message.isNotEmpty
              ? error.message
              : _failureMessage,
        ),
      );
      return;
    }
    if (_queue.isNotEmpty) await _next();
  }

  void _closeServices(CreatePostRequest draft) {
    for (final image in draft.images) {
      _services.remove(image.localId)?.close();
    }
  }

  void _reset() {
    _generation++;
    _cancel?.cancel();
    _cancel = null;
    _current = null;
    _queue.clear();
    for (final service in _services.values) {
      service.close();
    }
    _services.clear();
  }

  void _sessionChanged() {
    if (isClosed || _preferences.sessionRevision == _session) return;
    _session = _preferences.sessionRevision;
    _reset();
    emit(const PostUploadIdle());
  }

  @override
  Future<void> close() {
    _preferences.removeListener(_sessionChanged);
    _reset();
    return super.close();
  }
}
