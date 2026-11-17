import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/media/media_upload_service.dart';
import 'package:travibe/features/profile/data/profile_avatar_repo.dart';

part 'profile_picture_upload_state.dart';

/// Picture-progress mapping shared by the profile uploaders (mirrors Stories):
/// upload 0.1–0.85, processing 0.85, attaching 0.95. Never 0, so the white
/// ring (not the fallback spinner) shows from the first frame.
double pictureUploadFraction(int sent, int total) =>
    total <= 0 ? .1 : .1 + .75 * (sent / total).clamp(0.0, 1.0);

/// Uploads a picked Edit Profile picture and holds its media ID until Save
/// Changes commits it with the rest of the form. Nothing is attached to the
/// profile here, so closing or discarding keeps the old picture.
class ProfilePictureUploadCubit extends Cubit<ProfilePictureUploadState> {
  ProfilePictureUploadCubit({
    MediaUploadService Function()? uploads,
    PreferencesManager? preferences,
  }) : _uploads = uploads ?? MediaUploadService.new,
       _preferences = preferences ?? PreferencesManager(),
       super(const ProfilePictureIdle()) {
    _session = _preferences.sessionRevision;
    _preferences.addListener(_sessionChanged);
  }

  final MediaUploadService Function() _uploads;
  final PreferencesManager _preferences;
  late int _session;
  int _generation = 0;
  CancelToken? _cancel;
  MediaUploadService? _service;
  ProfileAvatarDraft? _draft;

  bool get uploading => state is ProfilePictureUploading;

  /// The uploaded, not yet saved picture's media ID.
  int? get mediaId => switch (state) {
    ProfilePictureDone(:final mediaId) => mediaId,
    _ => null,
  };

  /// Starts uploading [draft], replacing any earlier picture.
  Future<void> start(ProfileAvatarDraft draft) {
    if (isClosed) return Future.value();
    _reset();
    _draft = draft;
    return _run();
  }

  Future<void> retry() {
    if (isClosed || state is! ProfilePictureFailed || _draft == null) {
      return Future.value();
    }
    return _run();
  }

  /// Drops the picked picture (also mid-upload); the profile is unchanged.
  void discard() {
    if (isClosed) return;
    _reset();
    emit(const ProfilePictureIdle());
  }

  Future<void> _run() async {
    final draft = _draft!;
    final generation = ++_generation;
    final cancel = _cancel = CancelToken();
    bool active() =>
        !isClosed && generation == _generation && !cancel.isCancelled;
    void progress(double value) {
      if (active()) emit(ProfilePictureUploading(draft.bytes, progress: value));
    }

    progress(.1);
    try {
      final contentType = draft.contentType;
      if (contentType == null) throw StateError('Unsupported image type');
      final mediaId = await (_service ??= _uploads()).upload(
        filename: draft.name,
        contentType: contentType,
        bytes: draft.bytes,
        isActive: active,
        cancelToken: cancel,
        onStage: (stage) {
          if (stage == MediaUploadStage.processing) progress(.85);
        },
        onProgress: (sent, total) {
          if (total > 0) progress(pictureUploadFraction(sent, total));
        },
      );
      if (!active()) return;
      _closeService();
      emit(ProfilePictureDone(draft.bytes, mediaId: mediaId));
    } catch (_) {
      if (!active()) return;
      emit(ProfilePictureFailed(draft.bytes));
    }
  }

  void _closeService() {
    _service?.close();
    _service = null;
  }

  void _reset() {
    _generation++;
    _cancel?.cancel();
    _cancel = null;
    _closeService();
    _draft = null;
  }

  void _sessionChanged() {
    if (isClosed || _preferences.sessionRevision == _session) return;
    _session = _preferences.sessionRevision;
    _reset();
    emit(const ProfilePictureIdle());
  }

  @override
  Future<void> close() {
    _preferences.removeListener(_sessionChanged);
    _reset();
    return super.close();
  }
}
