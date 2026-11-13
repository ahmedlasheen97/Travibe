import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/places/city_places_provider.dart';
import 'package:travibe/core/media/upload_diagnostics.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'package:travibe/features/profile/data/profile_repo.dart';

import 'package:travibe/features/profile/data/profile_update.dart';
import 'dart:async';
import 'current_user_cubit.dart';

part 'profile_state.dart';

class ProfileCubit extends Cubit<ProfileState> {
  ProfileCubit({
    ProfileRepo? profileRepo,
    this.userId,
    CurrentUserCubit? currentUser,
  }) : _profileRepo = profileRepo ?? ProfileRepo(),
       _currentUser = currentUser,
       super(
         userId == null && currentUser?.state.profile != null
             ? ProfileLoaded(currentUser!.state.profile!)
             : ProfileInitial(),
       ) {
    PreferencesManager().addListener(_sessionChanged);
    if (userId == null && currentUser != null) {
      // Baseline for follower-count deltas from the shared current user.
      _lastCurrentUser = currentUser.state.profile;
      _userSubscription = currentUser.stream.listen((state) {
        if (isClosed) return;
        final profile = state.profile;
        if (profile == null && !PreferencesManager().hasSession) {
          ++_generation;
          _loading = null;
          emit(ProfileInitial());
        } else if (profile != null &&
            state.saving == null &&
            !state.loading &&
            !identical(profile, _lastCurrentUser)) {
          final previous = _lastCurrentUser;
          _lastCurrentUser = profile;
          final existing = this.state;
          if (existing is ProfileLoaded && existing.profile.id == profile.id) {
            // Apply only follower-count *changes* (accepted requests), never
            // a possibly older absolute count from the shared resource.
            final before = previous?.followersCount;
            final after = profile.followersCount;
            final current = existing.profile.followersCount;
            final delta = before != null && after != null && current != null
                ? after - before
                : 0;
            var next = existing.profile.withSettings(profile);
            if (delta != 0) {
              next = next.withFollowersCount(
                (current! + delta).clamp(0, 1 << 31).toInt(),
              );
            }
            emit(
              ProfileLoaded(
                next,
                refreshing: existing.refreshing,
                error: existing.error,
              ),
            );
          }
        }
      });
    }
  }
  void _sessionChanged() {
    if (isClosed) return;
    ++_generation;
    _loading = null;
    _lastCurrentUser = null;
    emit(ProfileInitial());
    if (PreferencesManager().hasSession) loadProfile();
  }

  StreamSubscription<CurrentUserState>? _userSubscription;
  ProfileModel? _lastCurrentUser;
  final CurrentUserCubit? _currentUser;

  final ProfileRepo _profileRepo;
  final int? userId;
  int _generation = 0;
  Future<void>? _loading;

  Future<void> loadProfile({bool force = false}) {
    if (isClosed) return Future.value();
    if (!force && _loading != null) return _loading!;
    final generation = ++_generation;
    final previous = state;
    emit(
      previous is ProfileLoaded
          ? ProfileLoaded(previous.profile, refreshing: true)
          : ProfileLoading(),
    );
    final request = _load(generation);
    _loading = request;
    return request.whenComplete(() {
      if (generation == _generation) _loading = null;
    });
  }

  Future<void> refresh() => loadProfile(force: true);

  Future<void> _load(int generation) async {
    final sessionRevision = PreferencesManager().sessionRevision;
    try {
      final profile = userId == null
          ? await _profileRepo.getMyProfile()
          : await _profileRepo.getPublicProfile(userId!);
      if (isClosed ||
          generation != _generation ||
          sessionRevision != PreferencesManager().sessionRevision) {
        return;
      }
      if (userId == null && profile != null) {
        _currentUser?.cacheProfile(profile, expectedSession: sessionRevision);
      }
      emit(
        profile == null
            ? ProfileUnavailable()
            : ProfileLoaded(
                userId == null
                    ? profile.withSettings(_currentUser?.state.profile)
                    : profile,
              ),
      );
    } catch (error) {
      if (isClosed ||
          generation != _generation ||
          sessionRevision != PreferencesManager().sessionRevision) {
        return;
      }
      final failure = error is ApiError
          ? error
          : ApiError(message: 'Unable to load this profile. Please try again.');
      final current = state;
      emit(
        current is ProfileLoaded &&
                ![401, 403, 404].contains(failure.statusCode)
            ? ProfileLoaded(current.profile, error: failure)
            : ProfileFailure(failure),
      );
    }
  }

  Future<void> updateMyProfile(
    ProfileUpdate update, {
    required String expectedId,
  }) async {
    if (isClosed ||
        userId != null ||
        state is! ProfileLoaded ||
        (state as ProfileLoaded).profile.id != expectedId) {
      throw ApiError(message: 'Open your own profile before editing.');
    }
    final sessionRevision = PreferencesManager().sessionRevision;
    await _profileRepo.updateProfile(update);
    if (isClosed || sessionRevision != PreferencesManager().sessionRevision) {
      throw ApiError(message: 'Your session changed. Reopen your profile.');
    }
    // Never let a pre-save read or old values replace the committed profile.
    ++_generation;
    _loading = null;
    emit(ProfileLoading());
    await refresh();
    final refreshed = state;
    if (refreshed is ProfileFailure) {
      logUploadFailure(UploadDiagnosticStage.profileRefresh, refreshed.error);
    } else if (refreshed is ProfileLoaded && refreshed.error != null) {
      logUploadFailure(UploadDiagnosticStage.profileRefresh, refreshed.error!);
    }
  }

  Future<String?> saveCurrentLocation(CitySelection? city) async {
    if (isClosed || userId != null || state is! ProfileLoaded) {
      throw ApiError(
        message: 'Reload your own profile before saving its current city.',
      );
    }
    final previous = (state as ProfileLoaded).profile;
    final session = PreferencesManager().sessionRevision;
    final generation = ++_generation;
    _loading = null;
    ProfileModel profile;
    if (_currentUser != null) {
      final saved = city == null
          ? await _currentUser.clearLocation()
          : await _currentUser.saveLocation(city);
      if (!saved) {
        throw _currentUser.state.error ??
            ApiError(message: 'Unable to save your current city.');
      }
      profile = previous.withLocation(
        _currentUser.state.profile?.currentLocation,
      );
    } else if (city == null) {
      await _profileRepo.clearLocation();
      profile = previous.withLocation(null);
    } else {
      final saved = await _profileRepo.saveLocation(city);
      if (saved.id != previous.id) {
        throw ApiError(
          message:
              'The server returned a different account. Reopen Edit Profile.',
        );
      }
      profile = previous.withLocation(saved.currentLocation);
    }
    if (isClosed ||
        session != PreferencesManager().sessionRevision ||
        generation != _generation) {
      throw ApiError(message: 'Your profile changed. Reopen Edit Profile.');
    }
    emit(ProfileLoaded(profile));
    return profile.currentLocation;
  }

  Future<void> reportUser(String reason) async {
    if (isClosed ||
        userId == null ||
        state is! ProfileLoaded ||
        (state as ProfileLoaded).profile.isMe == true) {
      throw ApiError(message: 'This profile is unavailable.');
    }
    final session = PreferencesManager().sessionRevision;
    await _profileRepo.reportUser('$userId', reason);
    if (isClosed || session != PreferencesManager().sessionRevision) {
      throw ApiError(message: 'Your session changed. Reopen this profile.');
    }
  }

  /// A confirmed local block must also invalidate in-flight profile reads.
  void publicProfileUnavailable() {
    if (isClosed || userId == null) return;
    ++_generation;
    _loading = null;
    emit(ProfileUnavailable());
  }

  @override
  Future<void> close() {
    PreferencesManager().removeListener(_sessionChanged);
    _userSubscription?.cancel();
    ++_generation;
    return super.close();
  }
}
