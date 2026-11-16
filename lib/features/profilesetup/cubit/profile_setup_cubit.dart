import 'dart:async';
import 'package:travibe/core/places/city_places_provider.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/data/profile_repo.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:travibe/core/media/media_upload_service.dart';
import 'package:travibe/features/profile/data/profile_avatar_repo.dart';
import 'package:travibe/features/profilesetup/data/profile_identity_validation.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/material.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/profilesetup/data/profile_setup_repo.dart';
import 'package:travibe/features/profilesetup/data/reference_item.dart';
import 'package:travibe/features/profilesetup/data/profile_selection_options.dart';
import 'package:travibe/features/profilesetup/data/profile_setup_result.dart';

part 'profile_setup_state.dart';

class ProfileSetupCubit extends Cubit<ProfileSetupState> {
  ProfileSetupCubit({
    ProfileSetupRepo? repo,
    ProfileRepo? profileRepo,
    this.currentUser,
    ProfileAvatarRepo? avatarRepo,
    MediaUploadService? mediaUpload,
  }) : _repo = repo ?? ProfileSetupRepo(),
       _profiles = profileRepo ?? ProfileRepo(),
       _avatarRepo = avatarRepo ?? ProfileAvatarRepo(),
       _mediaUpload = mediaUpload ?? MediaUploadService(),
       _ownsUpload = mediaUpload == null,
       super(const ProfileSetupState()) {
    fullNameController.addListener(_identityChanged);
    PreferencesManager().addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (isClosed) return;
    _city = null;
    ++_avatarGeneration;
    _uploadCancel?.cancel();
    _repo.clearSessionSelections();
    if (_ownsUpload) {
      _mediaUpload.close();
      _mediaUpload = MediaUploadService();
    }
    _readyMediaId = null;
    _avatarAttached = false;
    _readyAvatar = null;
    _restoring = false;
    _identityEdited = false;
    _usernameDebounce?.cancel();
    ++_usernameRequestId;
    fullNameController.clear();
    usernameController.clear();
    _identityEdited = false;
    emit(const ProfileSetupState());
    if (pageController.hasClients) pageController.jumpToPage(0);
  }

  final ProfileSetupRepo _repo;
  final ProfileRepo _profiles;
  final CurrentUserCubit? currentUser;
  final ProfileAvatarRepo _avatarRepo;
  MediaUploadService _mediaUpload;
  final bool _ownsUpload;
  CancelToken? _uploadCancel;
  int _avatarGeneration = 0;
  int? _readyMediaId;
  bool _avatarAttached = false;
  ProfileAvatarDraft? _readyAvatar;
  bool _restoring = false;
  bool _identityEdited = false;
  void _identityChanged() {
    _identityEdited = true;
    if (!isClosed && state.fieldErrors.containsKey('full_name')) {
      emit(
        state.copyWith(
          fieldErrors: Map.of(state.fieldErrors)..remove('full_name'),
        ),
      );
    }
  }

  Future<void> restore() async {
    if (isClosed || _restoring) return;
    _restoring = true;
    final session = PreferencesManager().sessionRevision;
    emit(state.copyWith(restoring: true, clearRestoreError: true));
    try {
      final profile =
          currentUser?.state.profile ??
          await _profiles.getMyProfile().timeout(const Duration(seconds: 12));
      if (isClosed || session != PreferencesManager().sessionRevision) return;
      if (!_identityEdited) {
        fullNameController.text = profile.name ?? '';
        usernameController.text = profile.username ?? '';
        _identityEdited = false;
      }
      _repo.restoreSelections(profile);
      emit(
        state.copyWith(
          restoring: false,
          avatarUrl: profile.avatarUrl,
          usernameStatus:
              !_identityEdited && (profile.username?.isNotEmpty ?? false)
              ? UsernameStatus.available
              : null,
          normalizedUsername: !_identityEdited ? profile.username : null,
          languages: state.languages.isEmpty
              ? profile.languageSelections
                    .map(
                      (e) =>
                          profileLanguageSlugs.entries
                              .where((m) => m.value == e.slug)
                              .map((m) => m.key)
                              .firstOrNull ??
                          e.slug,
                    )
                    .toList()
              : null,
          interests: state.interests.isEmpty
              ? profile.interestSelections
                    .map(
                      (e) =>
                          profileInterestSlugs.entries
                              .where((m) => m.value == e.slug)
                              .map((m) => m.key)
                              .firstOrNull ??
                          e.slug,
                    )
                    .toList()
              : null,
          travelStyles: state.travelStyles.isEmpty
              ? profile.travelStyleSelections.map((e) => e.slug).toList()
              : null,
        ),
      );
    } catch (_) {
      if (!isClosed && session == PreferencesManager().sessionRevision) {
        emit(
          state.copyWith(
            restoring: false,
            restoreError:
                'Unable to restore saved profile details. Retry, or keep editing your details.',
          ),
        );
      }
    } finally {
      if (session == PreferencesManager().sessionRevision) _restoring = false;
    }
  }

  CitySelection? _city;
  Future<void> setCity(CitySelection city) async {
    if (isClosed || state.isSaving) return;
    final session = PreferencesManager().sessionRevision;
    _city = city;
    emit(state.copyWith(status: ProfileSetupStatus.saving, errorMessage: ''));
    try {
      await _commitCity();
      if (!isClosed && session == PreferencesManager().sessionRevision) {
        emit(state.copyWith(status: ProfileSetupStatus.editing));
      }
    } catch (error) {
      if (!isClosed && session == PreferencesManager().sessionRevision) {
        emit(
          state.copyWith(
            status: ProfileSetupStatus.failure,
            errorMessage: _messageFrom(error),
          ),
        );
      }
    }
  }

  Future<void> _commitCity() async {
    final city = _city;
    if (city == null) return;
    final session = PreferencesManager().sessionRevision;
    String? location;
    if (currentUser != null) {
      if (!await currentUser!.saveLocation(city)) {
        throw currentUser!.state.error ??
            ApiError(message: 'Unable to save your current city.');
      }
      location = currentUser!.state.profile?.currentLocation;
    } else {
      location = (await _profiles.saveLocation(city)).currentLocation;
    }
    if (isClosed || session != PreferencesManager().sessionRevision) {
      throw ApiError(message: 'Your session changed.');
    }
    emit(state.copyWith(currentLocation: location));
    _city = null;
  }

  final pageController = PageController();
  final fullNameController = TextEditingController();
  final usernameController = TextEditingController();

  Timer? _usernameDebounce;
  int _usernameRequestId = 0;

  // ---------------- navigation ----------------

  void onPageChanged(int step) => emit(state.copyWith(step: step));

  /// Returns true if it went back a step; false means we're on step 0
  /// and the screen should pop instead.
  bool goBack() {
    if (state.step == 0) return false;
    _goToStep(state.step - 1);
    return true;
  }

  void _goToStep(int step) {
    if (isClosed) return;
    emit(state.copyWith(step: step));
    if (!pageController.hasClients) return;
    pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // ---------------- selections ----------------

  Future<void> pickAvatar() async {
    if (isClosed ||
        state.isSaving ||
        state.selectingAvatar ||
        state.uploadingAvatar) {
      return;
    }
    final generation = ++_avatarGeneration;
    final session = PreferencesManager().sessionRevision;
    bool active() =>
        !isClosed &&
        generation == _avatarGeneration &&
        session == PreferencesManager().sessionRevision;
    emit(state.copyWith(selectingAvatar: true, clearAvatarError: true));
    try {
      final draft = await _avatarRepo.pick();
      if (!active()) return;
      emit(state.copyWith(selectingAvatar: false));
      if (draft == null) return;
      _readyMediaId = null;
      _avatarAttached = false;
      _readyAvatar = null;
      emit(state.copyWith(avatar: draft));
      await uploadAvatar();
    } catch (error) {
      if (!active()) return;
      final message = switch (error) {
        InvalidProfileAvatar() =>
          'Choose a JPEG, PNG, GIF or WebP photo from your gallery.',
        PlatformException(
          code: 'photo_access_denied' || 'photo_access_restricted',
        ) =>
          'Allow photo access in device settings, then try again.',
        MissingPluginException() =>
          'Photo selection is unavailable on this device.',
        _ => 'Unable to select a photo. Please try again.',
      };
      emit(state.copyWith(selectingAvatar: false, avatarError: message));
    }
  }

  Future<void> uploadAvatar() async {
    final draft = state.avatar;
    if (isClosed ||
        draft == null ||
        state.uploadingAvatar ||
        state.selectingAvatar ||
        state.isSaving) {
      return;
    }
    final generation = _avatarGeneration;
    final session = PreferencesManager().sessionRevision;
    bool active() =>
        !isClosed &&
        generation == _avatarGeneration &&
        session == PreferencesManager().sessionRevision;
    final cancel = _uploadCancel = CancelToken();
    emit(state.copyWith(uploadingAvatar: true, clearAvatarError: true));
    try {
      final type = draft.contentType;
      if (type == null) {
        throw ApiError(message: 'Choose a JPEG, PNG, GIF or WebP photo.');
      }
      if (!identical(_readyAvatar, draft) || _readyMediaId == null) {
        final id = await _mediaUpload.upload(
          filename: draft.name,
          contentType: type,
          bytes: draft.bytes,
          isActive: active,
          cancelToken: cancel,
          onStage: (stage) {
            if (active()) emit(state.copyWith(avatarStage: stage));
          },
        );
        if (!active()) return;
        _readyAvatar = draft;
        _readyMediaId = id;
      }
      if (!active()) return;
      ProfileSetupResult? result;
      if (!_avatarAttached) {
        result = await _repo.saveSetup(avatarMediaId: _readyMediaId);
        if (!active()) return;
        _avatarAttached = true;
        _accept(result);
      }
      var profile = result?.profile;
      // PATCH commits the attachment. If its resource is sparse, verify via GET
      // without repeating either the upload or the attachment on retry.
      if (currentUser != null ||
          result == null ||
          !result.resourceFields.contains('avatar_url') ||
          profile?.avatarUrl == null) {
        profile = await _profiles.getMyProfile().timeout(
          const Duration(seconds: 12),
        );
      }
      if (!active()) return;
      if (profile?.avatarUrl == null) {
        throw ApiError(
          message:
              'The photo was saved but its preview is not available yet. Retry to refresh it.',
        );
      }
      currentUser?.cacheProfile(profile!, expectedSession: session);
      emit(
        state.copyWith(
          uploadingAvatar: false,
          clearAvatar: true,
          avatarUrl: profile!.avatarUrl,
          clearAvatarError: true,
        ),
      );
      _readyAvatar = null;
      _readyMediaId = null;
      _avatarAttached = false;
    } catch (error) {
      if (active()) {
        emit(
          state.copyWith(
            uploadingAvatar: false,
            avatarError: _messageFrom(error),
          ),
        );
      }
    }
  }

  void discardAvatar() {
    ++_avatarGeneration;
    _uploadCancel?.cancel();
    _readyAvatar = null;
    _readyMediaId = null;
    _avatarAttached = false;
    if (!isClosed) {
      emit(
        state.copyWith(
          clearAvatar: true,
          clearAvatarError: true,
          selectingAvatar: false,
          uploadingAvatar: false,
        ),
      );
    }
  }

  Future<void> loadCatalogs() => loadCatalog(ReferenceKind.travelStyles);

  final Set<ReferenceKind> _loadingCatalogs = {};
  Future<void> loadCatalog(ReferenceKind kind) async {
    if (isClosed || !_loadingCatalogs.add(kind)) return;
    emit(
      state.copyWith(
        catalogs: {...state.catalogs, kind: const ReferenceCatalog()},
      ),
    );
    try {
      final items = await _repo.loadCatalog(kind);
      if (isClosed) return;
      emit(
        state.copyWith(
          catalogs: {
            ...state.catalogs,
            kind: ReferenceCatalog(status: CatalogStatus.loaded, items: items),
          },
        ),
      );
      // A catalog refresh must not silently delete previously saved choices.
    } catch (e) {
      if (!isClosed) {
        emit(
          state.copyWith(
            catalogs: {
              ...state.catalogs,
              kind: ReferenceCatalog(
                status: CatalogStatus.failure,
                error: _messageFrom(e),
              ),
            },
          ),
        );
      }
    } finally {
      _loadingCatalogs.remove(kind);
    }
  }

  void _select(ReferenceKind kind, List<String> value) {
    final catalog = state.catalog(kind);
    final current = switch (kind) {
      ReferenceKind.languages => state.languages,
      ReferenceKind.interests => state.interests,
      ReferenceKind.travelStyles => state.travelStyles,
    };
    if (state.isSaving ||
        catalog.status != CatalogStatus.loaded ||
        value.length > kind.limit ||
        value.toSet().length != value.length ||
        value.any(
          (slug) =>
              !current.contains(slug) &&
              !catalog.items.any((item) => item.slug == slug),
        )) {
      return;
    }
    final selected = List<String>.unmodifiable(value);
    emit(switch (kind) {
      ReferenceKind.languages => state.copyWith(languages: selected),
      ReferenceKind.interests => state.copyWith(interests: selected),
      ReferenceKind.travelStyles => state.copyWith(travelStyles: selected),
    });
  }

  // These chips retain their original labels; the repository resolves slugs at save time.
  void setLanguages(List<String> value) {
    if (!state.isSaving &&
        value.length <= 4 &&
        value.toSet().length == value.length &&
        value.every(
          (value) =>
              profileLanguageOptions.contains(value) ||
              state.languages.contains(value),
        )) {
      emit(state.copyWith(languages: List.unmodifiable(value)));
    }
  }

  void setInterests(List<String> value) {
    if (!state.isSaving &&
        value.length <= 6 &&
        value.toSet().length == value.length &&
        value.every(
          (value) =>
              profileInterestOptions.contains(value) ||
              state.interests.contains(value),
        )) {
      emit(state.copyWith(interests: List.unmodifiable(value)));
    }
  }

  void setTravelStyles(List<String> value) =>
      _select(ReferenceKind.travelStyles, value);

  // ---------------- username availability ----------------

  void onUsernameChanged(String value) {
    _usernameDebounce?.cancel();
    _usernameRequestId++; // invalidates any check still in flight

    _identityEdited = true;
    final username = value.trim();
    final fields = Map<String, List<String>>.of(state.fieldErrors)
      ..remove('username');
    emit(state.copyWith(fieldErrors: fields));

    if (username.isEmpty) {
      emit(
        state.copyWith(
          usernameStatus: UsernameStatus.idle,
          usernameMessage: 'Username is required.',
          normalizedUsername: '',
        ),
      );
      return;
    }

    final shapeError = ProfileIdentityValidation.username(username);
    if (shapeError != null) {
      emit(
        state.copyWith(
          usernameStatus: UsernameStatus.invalid,
          usernameMessage: shapeError,
          normalizedUsername: '',
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        usernameStatus: UsernameStatus.checking,
        usernameMessage: '',
        normalizedUsername: '',
      ),
    );

    _usernameDebounce = Timer(
      const Duration(milliseconds: 500),
      () => _checkUsername(username),
    );
  }

  Future<void> _checkUsername(String username) async {
    final requestId = ++_usernameRequestId;
    try {
      final result = await _repo.checkUsername(username);
      if (requestId != _usernameRequestId || isClosed) return;

      emit(
        state.copyWith(
          usernameStatus: result.available
              ? UsernameStatus.available
              : UsernameStatus.taken,
          usernameMessage: '',
          normalizedUsername: result.username,
        ),
      );
    } catch (e) {
      if (requestId != _usernameRequestId || isClosed) return;

      emit(
        state.copyWith(
          usernameStatus: UsernameStatus.invalid,
          usernameMessage: _messageFrom(e),
          normalizedUsername: '',
        ),
      );
    }
  }

  // ---------------- saving ----------------

  Future<void> saveBasicInfo() async {
    if (isClosed ||
        state.selectingAvatar ||
        state.uploadingAvatar ||
        state.usernameStatus == UsernameStatus.checking ||
        state.avatar != null) {
      return;
    }
    final errors = <String, List<String>>{};
    final nameError = ProfileIdentityValidation.fullName(
      fullNameController.text,
    );
    final usernameError = ProfileIdentityValidation.username(
      usernameController.text,
    );
    if (nameError != null) errors['full_name'] = [nameError];
    if (usernameError != null) errors['username'] = [usernameError];
    if (state.usernameStatus == UsernameStatus.invalid) {
      errors['username'] = [
        state.usernameMessage.isNotEmpty
            ? state.usernameMessage
            : 'Check your username.',
      ];
    }
    if (state.usernameStatus == UsernameStatus.taken) {
      errors['username'] = ['Username is already taken.'];
    }
    if (errors.isNotEmpty) {
      emit(state.copyWith(fieldErrors: errors));
      return;
    }
    final ok = await _save(() async {
      await _commitCity();
      return _repo.saveSetup(
        fullName: fullNameController.text.trim(),
        username: state.normalizedUsername.isNotEmpty
            ? state.normalizedUsername
            : usernameController.text.trim(),
      );
    });
    if (ok != null) _navigate(ok);
  }

  Future<void> saveLanguagesAndInterests() async {
    // Nothing selected, nothing to save.
    if (state.languages.isEmpty && state.interests.isEmpty) {
      _goToStep(2);
      return;
    }

    final ok = await _save(
      () => _repo.saveSetup(
        languages: state.languages.isEmpty ? null : state.languages,
        interests: state.interests.isEmpty ? null : state.interests,
      ),
    );
    if (ok != null) _navigate(ok);
  }

  Future<void> finish() async {
    final ok = await _save(() async {
      final saved = await _repo.saveSetup(travelStyles: state.travelStyles);
      if (isClosed) return saved;
      _accept(saved);
      // The server decides readiness, including selections saved in earlier
      // sessions. Keep the existing completion route only for its review state.
      if (!saved.profileCompleted && saved.step == ProfileSetupStep.review) {
        return _repo.completeSetup();
      }
      return saved;
    });

    if (ok != null) _navigate(ok);
  }

  void _accept(ProfileSetupResult result) {
    var profile = result.profile;
    final previous = currentUser?.state.profile;
    if (profile != null && previous != null && previous.id != profile.id) {
      throw ApiError(message: 'Your account changed. Reopen profile setup.');
    }
    if (profile != null &&
        result.resourceFields.containsAll(const {
          'name',
          'username',
          'email',
          'email_verified_at',
          'profile_completed',
          'avatar_url',
        })) {
      if (!profile.locationIncluded && previous?.locationIncluded == true) {
        profile = profile.withLocation(previous?.currentLocation);
      }
      currentUser?.cacheProfile(
        profile,
        expectedSession: PreferencesManager().sessionRevision,
      );
    }
    List<String> labels(Iterable<String> slugs, Map<String, String> mapping) =>
        List.unmodifiable(
          slugs.map(
            (slug) =>
                mapping.entries
                    .where((entry) => entry.value == slug)
                    .map((entry) => entry.key)
                    .firstOrNull ??
                slug,
          ),
        );
    emit(
      state.copyWith(
        result: result,
        languages:
            result.resourceFields.contains('languages_spoken') ||
                result.resourceFields.contains('languages')
            ? labels(
                profile!.languageSelections.map((item) => item.slug),
                profileLanguageSlugs,
              )
            : null,
        interests: result.resourceFields.contains('interests')
            ? labels(
                profile!.interestSelections.map((item) => item.slug),
                profileInterestSlugs,
              )
            : null,
        travelStyles: result.resourceFields.contains('travel_styles')
            ? List.unmodifiable(
                profile!.travelStyleSelections.map((item) => item.slug),
              )
            : null,
      ),
    );
  }

  void _navigate(ProfileSetupResult result) {
    if (result.profileCompleted) {
      emit(state.copyWith(status: ProfileSetupStatus.completed));
    } else if (result.step == ProfileSetupStep.complete) {
      emit(
        state.copyWith(
          status: ProfileSetupStatus.failure,
          errorMessage:
              'The server has not confirmed profile completion. Please try again.',
        ),
      );
    } else {
      _goToStep(result.step.page);
    }
  }

  /// Runs [action] with saving/failure bookkeeping; only parsed server results
  /// can advance the wizard or confirm completion.
  Future<ProfileSetupResult?> _save(
    Future<ProfileSetupResult> Function() action,
  ) async {
    if (isClosed ||
        state.isSaving ||
        state.selectingAvatar ||
        state.uploadingAvatar) {
      return null;
    }

    final session = PreferencesManager().sessionRevision;
    emit(
      state.copyWith(
        status: ProfileSetupStatus.saving,
        errorMessage: '',
        fieldErrors: const {},
      ),
    );
    try {
      final result = await action();
      if (isClosed || session != PreferencesManager().sessionRevision) {
        return null;
      }
      _accept(result);
      if (currentUser != null &&
          !result.resourceFields.containsAll(const {
            'name',
            'username',
            'email',
            'email_verified_at',
            'profile_completed',
            'avatar_url',
          })) {
        unawaited(currentUser!.load());
      }
      emit(state.copyWith(status: ProfileSetupStatus.editing));
      return result;
    } catch (e) {
      if (isClosed || session != PreferencesManager().sessionRevision) {
        return null;
      }
      emit(
        state.copyWith(
          status: ProfileSetupStatus.failure,
          errorMessage: _messageFrom(e),
          fieldErrors: e is ApiError ? e.fieldErrors : const {},
          usernameStatus: e is ApiError && e.fieldErrors.containsKey('username')
              ? UsernameStatus.invalid
              : null,
          usernameMessage: e is ApiError
              ? e.fieldErrors['username']?.firstOrNull
              : null,
        ),
      );
      return null;
    }
  }

  String _messageFrom(Object e) => ApiError.messageOf(e);

  @override
  Future<void> close() {
    PreferencesManager().removeListener(_sessionChanged);
    _usernameDebounce?.cancel();
    ++_avatarGeneration;
    _uploadCancel?.cancel();
    if (_ownsUpload) _mediaUpload.close();
    fullNameController.removeListener(_identityChanged);
    pageController.dispose();
    fullNameController.dispose();
    usernameController.dispose();
    return super.close();
  }
}
