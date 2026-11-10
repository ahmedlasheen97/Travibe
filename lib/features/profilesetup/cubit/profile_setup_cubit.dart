import 'dart:async';
import 'package:travibe/core/places/city_places_provider.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/data/profile_repo.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'dart:io';

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
  }) : _repo = repo ?? ProfileSetupRepo(),
       _profiles = profileRepo ?? ProfileRepo(),
       super(const ProfileSetupState()) {
    PreferencesManager().addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (isClosed) return;
    _city = null;
    _usernameDebounce?.cancel();
    ++_usernameRequestId;
    fullNameController.clear();
    usernameController.clear();
    emit(const ProfileSetupState());
    if (pageController.hasClients) pageController.jumpToPage(0);
  }

  final ProfileSetupRepo _repo;
  final ProfileRepo _profiles;
  final CurrentUserCubit? currentUser;
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

  void setAvatar(File file) => emit(state.copyWith(avatarFile: file));
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

    final username = value.trim();

    if (username.isEmpty) {
      emit(
        state.copyWith(
          usernameStatus: UsernameStatus.idle,
          usernameMessage: '',
          normalizedUsername: '',
        ),
      );
      return;
    }

    if (username.length < 3 || username.runes.length > 30) {
      emit(
        state.copyWith(
          usernameStatus: UsernameStatus.invalid,
          usernameMessage: username.length < 3
              ? 'At least 3 characters'
              : 'At most 30 characters',
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
    final profile = result.profile;
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
    if (isClosed || state.isSaving) return null;

    final session = PreferencesManager().sessionRevision;
    emit(state.copyWith(status: ProfileSetupStatus.saving, errorMessage: ''));
    try {
      final result = await action();
      if (isClosed || session != PreferencesManager().sessionRevision) {
        return null;
      }
      _accept(result);
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
        ),
      );
      return null;
    }
  }

  String _messageFrom(Object e) =>
      e is ApiError ? e.message : 'Something went wrong';

  @override
  Future<void> close() {
    PreferencesManager().removeListener(_sessionChanged);
    _usernameDebounce?.cancel();
    pageController.dispose();
    fullNameController.dispose();
    usernameController.dispose();
    return super.close();
  }
}
