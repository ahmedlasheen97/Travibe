import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/media/media_upload_service.dart';
import 'package:travibe/core/media/upload_diagnostics.dart';
import 'package:travibe/features/profile/data/profile_avatar_repo.dart';

part 'profile_picture_upload_state.dart';

/// Attaches an uploaded media ID to the profile (PATCH avatar_media_id).
typedef ProfilePictureAttach = Future<void> Function(int mediaId);

/// Uploads a new profile picture in the background (Root-scoped, like posts),
/// so Edit Profile stays usable and can be closed while the toast reports
/// progress. A failure keeps the uploaded media ID, so Retry only re-attaches.
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
  ProfilePictureAttach? _attach;
  int? _mediaId;
  Completer<void>? _running;

  bool get uploading => state is ProfilePictureUploading;

  /// Starts uploading [draft], replacing any earlier picture in flight.
  Future<void> start(
    ProfileAvatarDraft draft, {
    required ProfilePictureAttach attach,
  }) {
    if (isClosed) return Future.value();
    _reset();
    _draft = draft;
    _attach = attach;
    return _run();
  }

  Future<void> retry() {
    if (isClosed || state is! ProfilePictureFailed || _draft == null) {
      return Future.value();
    }
    return _run();
  }

  /// Drops a failed or finished picture; the server avatar is unchanged.
  void discard() {
    if (isClosed || uploading) return;
    _reset();
    emit(const ProfilePictureIdle());
  }

  /// Resolves once no upload is running: true unless the last one failed.
  Future<bool> settled() async {
    while (!isClosed && _running != null) {
      await _running!.future;
    }
    return state is! ProfilePictureFailed;
  }

  Future<void> _run() async {
    final draft = _draft!;
    final attach = _attach!;
    final generation = ++_generation;
    final cancel = _cancel = CancelToken();
    final running = _running = Completer<void>();
    bool active() =>
        !isClosed && generation == _generation && !cancel.isCancelled;
    var attaching = false;
    emit(ProfilePictureUploading(draft.bytes));
    try {
      final contentType = draft.contentType;
      if (contentType == null) throw StateError('Unsupported image type');
      final mediaId =
          _mediaId ??
          await (_service ??= _uploads()).upload(
            filename: draft.name,
            contentType: contentType,
            bytes: draft.bytes,
            isActive: active,
            cancelToken: cancel,
            onStage: (_) {},
          );
      if (!active()) return;
      _mediaId = mediaId;
      attaching = true;
      await attach(mediaId);
      if (!active()) return;
      _closeService();
      _mediaId = null;
      emit(ProfilePictureDone(draft.bytes));
    } catch (error) {
      if (!active()) return;
      if (attaching) {
        logUploadFailure(UploadDiagnosticStage.profilePatch, error);
      }
      emit(ProfilePictureFailed(draft.bytes));
    } finally {
      if (identical(_running, running)) _running = null;
      if (!running.isCompleted) running.complete();
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
    _attach = null;
    _mediaId = null;
    final running = _running;
    _running = null;
    if (running != null && !running.isCompleted) running.complete();
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
