import 'dart:async';

import 'package:flutter/services.dart';
import 'package:travibe/core/media/upload_diagnostics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/profile/cubit/profile_cubit.dart';
import 'package:travibe/features/profile/cubit/profile_picture_upload_cubit.dart';
import 'package:travibe/features/profile/data/profile_avatar_repo.dart';
import 'package:travibe/features/profile/data/profile_update.dart';

class EditProfileState {
  const EditProfileState({
    this.saving = false,
    this.saved = false,
    this.error,
    this.selectingAvatar = false,
    this.avatarError,
    this.sessionChanged = false,
  });
  final bool saving;
  final bool saved;
  final ApiError? error;
  final bool selectingAvatar;

  /// Photo picker problems only; upload progress/failure is a toast.
  final String? avatarError;
  final bool sessionChanged;
}

class EditProfileCubit extends Cubit<EditProfileState> {
  EditProfileCubit(
    this.owner, {
    ProfilePictureUploadCubit? pictures,
    ProfileAvatarRepo? avatarRepo,
  }) : pictures = pictures ?? ProfilePictureUploadCubit(),
       _ownsPictures = pictures == null,
       _avatarRepo = avatarRepo ?? ProfileAvatarRepo(),
       _sessionRevision = PreferencesManager().sessionRevision,
       super(const EditProfileState()) {
    PreferencesManager().addListener(_sessionChanged);
  }
  final ProfileCubit owner;

  /// Background picture upload that Save Changes waits for.
  final ProfilePictureUploadCubit pictures;
  final bool _ownsPictures;
  final ProfileAvatarRepo _avatarRepo;
  final int _sessionRevision;
  int _selectionGeneration = 0;

  void _sessionChanged() {
    if (isClosed || _sessionRevision == PreferencesManager().sessionRevision) {
      return;
    }
    ++_selectionGeneration;
    emit(const EditProfileState(sessionChanged: true));
  }

  bool get _inactive => isClosed || state.sessionChanged || owner.isClosed;

  /// Picks a photo and starts uploading it right away; the picture is saved
  /// to the profile on its own, independently of Save Changes.
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
    emit(const EditProfileState(selectingAvatar: true));
    try {
      final selected = await _avatarRepo.pick();
      if (_inactive || generation != _selectionGeneration) return;
      if (owner.state is! ProfileLoaded ||
          (owner.state as ProfileLoaded).profile.id != profileId) {
        emit(const EditProfileState(sessionChanged: true));
        return;
      }
      emit(const EditProfileState());
      if (selected == null) return;
      final profile = owner;
      unawaited(
        pictures.start(
          selected,
          attach: (mediaId) => profile.updateMyProfile(
            ProfileUpdate({'avatar_media_id': mediaId}),
            expectedId: profileId,
          ),
        ),
      );
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
      emit(EditProfileState(avatarError: message));
    }
  }

  Future<bool> save(ProfileDraft draft) async {
    if (_inactive ||
        state.saving ||
        state.saved ||
        state.selectingAvatar ||
        !draft.isDirty) {
      return false;
    }
    // Only the picture upload flow can supply a media ID. Ignore draft IDs.
    final changes = Map<String, dynamic>.of(draft.changes)
      ..remove('avatar_media_id');
    if (changes.isEmpty && !draft.hasLocationChange) return false;
    emit(const EditProfileState(saving: true));
    var updatingProfile = false;
    var updatingLocation = false;
    try {
      ProfileUpdate(changes); // Validate fields before waiting.
      // Never save over a picture that is still uploading or failed. Only
      // wait when one is in flight, so ordinary saves stay synchronous.
      if (pictures.uploading) {
        await pictures.settled();
        if (_inactive) return false;
      }
      if (pictures.state is ProfilePictureFailed) {
        throw ApiError(
          message: 'Your picture didn’t upload. Retry it or dismiss it first.',
        );
      }
      if (owner.state is! ProfileLoaded &&
          draft.hasLocationChange &&
          changes.isEmpty) {
        await owner.refresh();
        if (_inactive) return false;
      }
      final active =
          !_inactive &&
          owner.userId == null &&
          owner.state is ProfileLoaded &&
          (owner.state as ProfileLoaded).profile.id == draft.profileId;
      if (!active) {
        throw ApiError(message: 'Open your own profile before editing.');
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
        draft.markSaved(update);
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
    PreferencesManager().removeListener(_sessionChanged);
    if (_ownsPictures) pictures.close();
    return super.close();
  }
}
