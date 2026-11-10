import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/places/city_places_provider.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import '../data/profile_model.dart';
import '../data/profile_repo.dart';
import '../data/settings_repo.dart';
import '../data/settings_update.dart';

class CurrentUserState {
  const CurrentUserState({
    this.profile,
    this.loading = false,
    this.saving,
    this.error,
    this.revision = 0,
  });
  final ProfileModel? profile;
  final bool loading;
  final String? saving;
  final ApiError? error;
  final int revision;
}

/// One authoritative, session-scoped current-user resource, shared by Settings,
/// the own profile and Buddies visibility. No independent visibility flag.
class CurrentUserCubit extends Cubit<CurrentUserState> {
  CurrentUserCubit({ProfileRepo? profileRepo, SettingsRepo? settingsRepo})
    : _profiles = profileRepo ?? ProfileRepo(),
      _settings = settingsRepo ?? SettingsRepo(),
      super(const CurrentUserState()) {
    _preferences.addListener(_sessionChanged);
  }
  final ProfileRepo _profiles;
  final SettingsRepo _settings;
  final _preferences = PreferencesManager();
  int _generation = 0;
  Future<void>? _pending;
  Set<String> get supportedCurrencies => {
    ..._settings.supportedCurrencies,
    if (state.profile?.currencyCode case final String code) code,
  };

  void _sessionChanged() {
    ++_generation;
    _pending = null;
    emit(CurrentUserState(revision: state.revision + 1));
    if (_preferences.hasSession) load();
  }

  Future<void> load() {
    if (isClosed || !_preferences.hasSession) return Future.value();
    if (_pending != null) return _pending!;
    if (state.saving != null) return Future.value();
    final generation = ++_generation;
    final session = _preferences.sessionRevision;
    emit(
      CurrentUserState(
        profile: state.profile,
        loading: true,
        revision: state.revision,
      ),
    );
    final request = _read(generation, session);
    _pending = request;
    return request.whenComplete(() {
      if (generation == _generation) _pending = null;
    });
  }

  Future<void> _read(int generation, int session) async {
    try {
      final profile = await _profiles.getMyProfile();
      if (!_current(generation, session)) return;
      await _presentation(profile, session);
      if (!_current(generation, session)) return;
      emit(CurrentUserState(profile: profile, revision: state.revision + 1));
    } catch (error) {
      if (!_current(generation, session)) return;
      emit(
        CurrentUserState(
          profile: state.profile,
          revision: state.revision,
          error: _error(error),
        ),
      );
    }
  }

  Future<void> update(SettingsUpdate update) async {
    if (isClosed ||
        state.saving != null ||
        !_preferences.hasSession ||
        state.profile?.hasSettings != true) {
      return;
    }
    final values = update.toJson();
    // Serialize whole-resource responses. Unrelated controls stay unchanged on
    // failure, and cannot race one another into overwriting newer settings.
    if (values.containsKey('currency_code') &&
        values['currency_code'] != null &&
        !supportedCurrencies.contains(values['currency_code'])) {
      emit(
        CurrentUserState(
          profile: state.profile,
          revision: state.revision,
          error: ApiError(
            message: 'This currency has not been confirmed as supported.',
          ),
        ),
      );
      return;
    }
    final generation = ++_generation;
    _pending = null;
    final session = _preferences.sessionRevision;
    final id = state.profile!.id;
    emit(
      CurrentUserState(
        profile: state.profile,
        saving: values.keys.first,
        revision: state.revision,
      ),
    );
    try {
      var profile = await _settings.update(update);
      if (!profile.locationIncluded &&
          state.profile?.locationIncluded == true) {
        profile = profile.withLocation(state.profile?.currentLocation);
      }
      if (!_current(generation, session)) return;
      if (profile.id != id) {
        throw ApiError(
          message: 'The server returned a different account. Reopen Settings.',
        );
      }
      profile = state.profile?.withSettings(profile) ?? profile;
      await _presentation(profile, session);
      if (!_current(generation, session)) return;
      emit(CurrentUserState(profile: profile, revision: state.revision + 1));
    } catch (error) {
      if (!_current(generation, session)) return;
      emit(
        CurrentUserState(
          profile: state.profile,
          revision: state.revision,
          error: _error(error),
        ),
      );
    }
  }

  /// Publish canonical profile fields while preserving an active settings write.
  void cacheProfile(ProfileModel profile, {required int expectedSession}) {
    if (isClosed ||
        !_preferences.hasSession ||
        expectedSession != _preferences.sessionRevision ||
        state.profile != null && state.profile!.id != profile.id) {
      return;
    }
    final saving = state.saving;
    if (saving == null) {
      ++_generation;
      _pending = null;
    }
    emit(
      CurrentUserState(
        profile: profile.withSettings(state.profile),
        saving: saving,
        revision: state.revision + 1,
      ),
    );
  }

  Future<bool> saveLocation(CitySelection city) => _location(city);
  Future<bool> clearLocation() => _location(null);

  Future<bool> _location(CitySelection? city) async {
    if (isClosed || !_preferences.hasSession || state.saving != null) {
      return false;
    }
    final generation = ++_generation;
    final session = _preferences.sessionRevision;
    _pending = null;
    final previous = state.profile;
    emit(
      CurrentUserState(
        profile: previous,
        saving: 'current_location',
        revision: state.revision,
      ),
    );
    try {
      ProfileModel profile;
      if (city == null) {
        await _profiles.clearLocation();
        if (!_current(generation, session)) return false;
        profile = (previous ?? await _profiles.getMyProfile()).withLocation(
          null,
        );
      } else {
        profile = await _profiles.saveLocation(city);
      }
      if (!_current(generation, session)) return false;
      if (previous != null && previous.id != profile.id) {
        throw ApiError(message: 'Your account changed. Reopen your profile.');
      }
      // A location response may be sparse; merge its canonical value into the
      // authoritative resource rather than clearing unrelated settings.
      emit(
        CurrentUserState(
          profile: previous?.withLocation(profile.currentLocation) ?? profile,
          revision: state.revision + 1,
        ),
      );
      return true;
    } catch (error) {
      if (_current(generation, session)) {
        emit(
          CurrentUserState(
            profile: previous,
            error: _error(error),
            revision: state.revision,
          ),
        );
      }
      return false;
    }
  }

  bool _current(int generation, int session) =>
      !isClosed &&
      generation == _generation &&
      session == _preferences.sessionRevision;
  Future<void> _presentation(ProfileModel profile, int session) async {
    if (!profile.hasSettings) return;
    await _preferences.saveUserPresentation(
      locale: profile.locale!,
      currency: profile.currencyCode,
      expectedSession: session,
    );
  }

  ApiError _error(Object error) => error is ApiError
      ? error
      : ApiError(message: 'Unable to update settings. Please try again.');
  @override
  Future<void> close() {
    ++_generation;
    _preferences.removeListener(_sessionChanged);
    return super.close();
  }
}
