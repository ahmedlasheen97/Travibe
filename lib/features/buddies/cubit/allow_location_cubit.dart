import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/places/city_places_provider.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/data/settings_update.dart';

/// "Turn On" / "Choose City" in the Show me in Buddies sheet. Never touches device
/// location: it uses the saved current city, or one the user searched for.
class AllowLocationState {
  const AllowLocationState({
    this.busy = false,
    this.locationSaved = false,
    this.enabled = false,
    this.error,
  });
  final bool busy, locationSaved, enabled;
  final String? error;
}

class AllowLocationCubit extends Cubit<AllowLocationState> {
  AllowLocationCubit({required this.currentUser})
    : super(const AllowLocationState()) {
    _preferences.addListener(_sessionChanged);
  }
  final CurrentUserCubit currentUser;
  final _preferences = PreferencesManager();
  int _generation = 0;
  void _sessionChanged() {
    ++_generation;
    if (!isClosed) emit(const AllowLocationState());
  }

  /// The user already has a current city: only turn visibility on.
  Future<void> turnOn() => _run(null);

  /// A city from the city search → save city → turn on.
  Future<void> chooseCity(CitySelection city) => _run(city);

  Future<void> _run(CitySelection? city) async {
    if (isClosed || state.busy || currentUser.state.saving != null) return;
    final generation = ++_generation;
    final session = _preferences.sessionRevision;
    bool current() =>
        !isClosed &&
        generation == _generation &&
        session == _preferences.sessionRevision;
    var saved = currentUser.state.profile?.currentLocation != null;
    emit(AllowLocationState(busy: true, locationSaved: saved));
    try {
      if (!_preferences.hasSession) {
        throw ApiError(message: 'Sign in to allow location.');
      }
      if (city != null) {
        if (!await currentUser.saveLocation(city)) {
          throw currentUser.state.error ??
              ApiError(message: 'Unable to save your current city. Try again.');
        }
        if (!current()) return;
        saved = true;
      } else if (!saved) {
        throw ApiError(message: 'Choose your current city first.');
      }
      if (currentUser.state.profile?.hasSettings != true) {
        await currentUser.load();
      }
      if (!current()) return;
      await currentUser.update(SettingsUpdate({'show_in_travel_buddy': true}));
      if (!current()) return;
      if (currentUser.state.error != null ||
          currentUser.state.profile?.showInTravelBuddy != true) {
        throw currentUser.state.error ??
            ApiError(message: 'Your city is saved. Retry turning on Buddies.');
      }
      emit(const AllowLocationState(locationSaved: true, enabled: true));
    } catch (error) {
      if (!current()) return;
      final message = error is ApiError
          ? error.message
          : 'Unable to turn on Buddies. Try again.';
      emit(AllowLocationState(locationSaved: saved, error: message));
    }
  }

  @override
  Future<void> close() {
    ++_generation;
    _preferences.removeListener(_sessionChanged);
    return super.close();
  }
}
