import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:travibe/core/media/media_upload_service.dart';
import 'package:travibe/core/media/upload_diagnostics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/profile/cubit/profile_cubit.dart';
import 'package:travibe/features/profile/data/profile_avatar_repo.dart';
import 'package:travibe/features/profile/data/profile_update.dart';

class EditProfileState {
  const EditProfileState({
    this.saving = false,
    this.saved = false,
    this.error,
    this.avatar,
    this.selectingAvatar = false,
    this.avatarError,
    this.sessionChanged = false,
    this.uploadStage,
  });
  final bool saving;
  final bool saved;
  final ApiError? error;
  final ProfileAvatarDraft? avatar;
  final bool selectingAvatar;
  final String? avatarError;
  final bool sessionChanged;
  final MediaUploadStage? uploadStage;
}

class EditProfileCubit extends Cubit<EditProfileState> {
  EditProfileCubit(
    this.owner, {
    ProfileAvatarRepo? avatarRepo,
    MediaUploadService? mediaUpload,
  }) : _avatarRepo = avatarRepo ?? ProfileAvatarRepo(),
       _mediaUpload = mediaUpload ?? MediaUploadService(),
       _ownsMediaUpload = mediaUpload == null,
       _sessionRevision = PreferencesManager().sessionRevision,
       super(const EditProfileState()) {
    PreferencesManager().addListener(_sessionChanged);
  }
  final ProfileCubit owner;
  final ProfileAvatarRepo _avatarRepo;
  final MediaUploadService _mediaUpload;
  final bool _ownsMediaUpload;
  CancelToken? _uploadCancel;
  ProfileAvatarDraft? _readyAvatar;
  int? _readyMediaId;
  final int _sessionRevision;
  int _selectionGeneration = 0;

  void _sessionChanged() {
    if (isClosed || _sessionRevision == PreferencesManager().sessionRevision) {
      return;
    }
    ++_selectionGeneration;
    _uploadCancel?.cancel();
    _readyAvatar = null;
    _readyMediaId = null;
    emit(const EditProfileState(sessionChanged: true));
  }

  bool get _inactive => isClosed || state.sessionChanged || owner.isClosed;

  Future<void> pickAvatar() async {
    if (_inactive ||
        state.selectingAvatar ||
        state.saving ||
        state.saved ||
        owner.userId != null ||
        owner.state is! ProfileLoaded) {
      return;
    }
    final profileId = (owner.state as ProfileLoaded).profile.id;
    final generation = ++_selectionGeneration;
    final previous = state.avatar;
    emit(EditProfileState(avatar: previous, selectingAvatar: true));
    try {
      final selected = await _avatarRepo.pick();
      if (_inactive || generation != _selectionGeneration) return;
      if (owner.state is! ProfileLoaded ||
          (owner.state as ProfileLoaded).profile.id != profileId) {
        emit(const EditProfileState(sessionChanged: true));
        return;
      }
      if (selected != null) {
        _readyAvatar = null;
        _readyMediaId = null;
      }
      emit(EditProfileState(avatar: selected ?? previous));
    } catch (error) {
      if (_inactive || generation != _selectionGeneration) return;
      if (owner.state is! ProfileLoaded ||
          (owner.state as ProfileLoaded).profile.id != profileId) {
        emit(const EditProfileState(sessionChanged: true));
        return;
      }
      final message = switch (error) {
        InvalidProfileAvatar() => 'Choose a valid image from your gallery.',
        MissingPluginException() =>
          'Photo selection is unavailable on this device.',
        PlatformException(
          code: 'photo_access_denied' || 'photo_access_restricted',
        ) =>
          'Allow photo access in device settings, then try again.',
        _ => 'Unable to select a photo. Please try again.',
      };
      emit(EditProfileState(avatar: previous, avatarError: message));
    }
  }

  /// Discards only the unsaved preview; never removes the server avatar.
  void discardAvatarPreview() {
    if (_inactive || state.selectingAvatar || state.saving) return;
    _readyAvatar = null;
    _readyMediaId = null;
    emit(const EditProfileState());
  }

  Future<bool> save(ProfileDraft draft) async {
    if (_inactive ||
        state.saving ||
        state.saved ||
        state.selectingAvatar ||
        (!draft.isDirty && state.avatar == null)) {
      return false;
    }
    // Only this verified upload flow can supply a media ID. Ignore draft IDs.
    final changes = Map<String, dynamic>.of(draft.changes)
      ..remove('avatar_media_id');
    final avatar = state.avatar;
    if (changes.isEmpty && avatar == null && !draft.hasLocationChange) {
      return false;
    }
    final avatarError = state.avatarError;
    emit(
      EditProfileState(saving: true, avatar: avatar, avatarError: avatarError),
    );
    var updatingProfile = false;
    var updatingLocation = false;
    var pendingAvatar = avatar;
    try {
      ProfileUpdate(changes); // Validate fields before starting an upload.
      if (owner.state is! ProfileLoaded &&
          draft.hasLocationChange &&
          changes.isEmpty &&
          avatar == null) {
        await owner.refresh();
        if (_inactive) return false;
      }
      bool active() =>
          !_inactive &&
          owner.userId == null &&
          owner.state is ProfileLoaded &&
          (owner.state as ProfileLoaded).profile.id == draft.profileId;
      if (!active()) {
        throw ApiError(message: 'Open your own profile before editing.');
      }
      if (avatar != null) {
        final contentType = avatar.contentType;
        if (contentType == null) {
          throw ApiError(message: 'Choose a JPEG, PNG, GIF or WebP photo.');
        }
        if (!identical(_readyAvatar, avatar) || _readyMediaId == null) {
          final cancel = _uploadCancel = CancelToken();
          final mediaId = await _mediaUpload.upload(
            filename: avatar.name,
            contentType: contentType,
            bytes: avatar.bytes,
            isActive: active,
            cancelToken: cancel,
            onStage: (stage) {
              if (active()) {
                emit(
                  EditProfileState(
                    saving: true,
                    avatar: avatar,
                    uploadStage: stage,
                  ),
                );
              }
            },
          );
          if (!active()) return false;
          _readyAvatar = avatar;
          _readyMediaId = mediaId;
        }
        if (!active()) return false;
        changes['avatar_media_id'] = _readyMediaId!;
        emit(EditProfileState(saving: true, avatar: avatar));
      }
      final update = ProfileUpdate(changes);
      if (!update.isEmpty) {
        updatingProfile = true;
        await owner.updateMyProfile(update, expectedId: draft.profileId);
        if (_inactive) return false;
        final currentOwner = owner.state;
        if (currentOwner is ProfileLoaded &&
            currentOwner.profile.id != draft.profileId) {
          emit(const EditProfileState(sessionChanged: true));
          return false;
        }
        // PATCH is committed even if its follow-up GET fails. Never replay it
        // because a later, separate location operation failed.
        draft.markSaved(
          ProfileUpdate(
            Map<String, dynamic>.of(changes)..remove('avatar_media_id'),
          ),
        );
        _readyAvatar = null;
        _readyMediaId = null;
        pendingAvatar = null;
        updatingProfile = false;
      }
      if (draft.hasLocationChange) {
        updatingLocation = true;
        if (owner.state is! ProfileLoaded) {
          throw ApiError(
            message:
                'Your profile changes were saved, but reloading failed. Retry to continue saving your current city.',
          );
        }
        final submitted = draft.currentLocation;
        final canonical = await owner.saveCurrentLocation(draft.selectedCity);
        if (_inactive) return false;
        draft.markLocationSaved(submitted: submitted, canonical: canonical);
      }
      if (draft.hasLocationChange ||
          draft.changes.keys.any((key) => key != 'avatar_media_id')) {
        // A later edit must stay pending even if this request has completed.
        emit(const EditProfileState());
        return false;
      }
      emit(const EditProfileState(saved: true));
      return true;
    } catch (error) {
      if (updatingProfile) {
        logUploadFailure(UploadDiagnosticStage.profilePatch, error);
      }
      if (!_inactive) {
        emit(
          EditProfileState(
            avatar: pendingAvatar,
            avatarError: avatarError,
            error: updatingLocation && error is ApiError
                ? ApiError(
                    message: error.message,
                    statusCode: error.statusCode,
                    fieldErrors: {
                      'current_location': [error.message],
                    },
                  )
                : error is ApiError
                ? error
                : ApiError(
                    message: 'Unable to save your profile. Please try again.',
                  ),
          ),
        );
      }
      return false;
    }
  }

  @override
  Future<void> close() {
    ++_selectionGeneration;
    _uploadCancel?.cancel();
    _readyAvatar = null;
    _readyMediaId = null;
    PreferencesManager().removeListener(_sessionChanged);
    if (_ownsMediaUpload) _mediaUpload.close();
    return super.close();
  }
}
