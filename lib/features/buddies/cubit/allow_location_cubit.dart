import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/location/device_location_service.dart';
import 'package:travibe/core/places/city_places_provider.dart';
import 'package:travibe/core/places/photon_city_places_provider.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/data/settings_update.dart';

class AllowLocationState {
  const AllowLocationState({
    this.busy = false,
    this.locationSaved = false,
    this.enabled = false,
    this.openSettings = false,
    this.error,
  });
  final bool busy, locationSaved, enabled, openSettings;
  final String? error;
}

class AllowLocationCubit extends Cubit<AllowLocationState> {
  AllowLocationCubit({
    required this.currentUser,
    DeviceLocationService? device,
    CityReverseGeocoder? geocoder,
  }) : device = device ?? GeolocatorDeviceLocationService(),
       geocoder = geocoder ?? PhotonCityPlacesProvider(),
       super(const AllowLocationState()) {
    _preferences.addListener(_sessionChanged);
  }
  final CurrentUserCubit currentUser;
  final DeviceLocationService device;
  final CityReverseGeocoder geocoder;
  final _preferences = PreferencesManager();
  int _generation = 0;
  void _sessionChanged() {
    ++_generation;
    if (!isClosed) emit(const AllowLocationState());
  }

  Future<void> allow() async {
    if (isClosed || state.busy || currentUser.state.saving != null) return;
    final generation = ++_generation;
    final session = _preferences.sessionRevision;
    bool current() =>
        !isClosed &&
        generation == _generation &&
        session == _preferences.sessionRevision;
    var saved =
        state.locationSaved &&
        currentUser.state.profile?.currentLocation != null;
    emit(AllowLocationState(busy: true, locationSaved: saved));
    try {
      if (!_preferences.hasSession) {
        throw ApiError(message: 'Sign in to allow location.');
      }
      if (!saved) {
        final coordinates = await device.locate();
        if (!current()) return;
        final city = await geocoder.reverse(
          coordinates.latitude,
          coordinates.longitude,
        );
        if (!current()) return;
        saved = await currentUser.saveLocation(city);
        if (!current()) return;
        if (!saved) {
          throw currentUser.state.error ??
              ApiError(message: 'Unable to save your current city. Try again.');
        }
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
            ApiError(
              message: 'Your location is saved. Retry enabling visibility.',
            );
      }
      emit(const AllowLocationState(locationSaved: true, enabled: true));
    } catch (error) {
      if (!current()) return;
      final message = switch (error) {
        DeviceLocationException e => e.message,
        CityPlacesException e => e.message,
        ApiError e => e.message,
        _ =>
          'Unable to get your location. Try again, or choose a city manually.',
      };
      emit(
        AllowLocationState(
          locationSaved: saved,
          openSettings: error is DeviceLocationException && error.openSettings,
          error: saved
              ? 'Your city was saved. Visibility could not be enabled. $message'
              : message,
        ),
      );
    }
  }

  @override
  Future<void> close() {
    ++_generation;
    _preferences.removeListener(_sessionChanged);
    return super.close();
  }
}
