import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/location/device_location_service.dart';
import 'package:travibe/core/places/city_places_provider.dart';
import 'package:travibe/core/places/device_city_reverse_geocoder.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/data/settings_update.dart';

/// Rounds a coordinate to 2 decimals (about 1 km), enough to find a city.
double coarseCoordinate(double value) => (value * 100).roundToDouble() / 100;

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
       geocoder = geocoder ?? DeviceCityReverseGeocoder(),
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

  /// The user already has a current city: only turn visibility on.
  Future<void> turnOn() => _run(null);

  /// Device location → reverse geocode → save city → turn on.
  Future<void> useLocation() => _run(() async {
    final coordinates = await device.locate();
    // Only the city leaves the device for Travibe; the reverse geocoder gets
    // coordinates coarsened to about 1 km.
    return geocoder.reverse(
      coarseCoordinate(coordinates.latitude),
      coarseCoordinate(coordinates.longitude),
    );
  });

  /// A city picked manually → save city → turn on.
  Future<void> chooseCity(CitySelection city) => _run(() async => city);

  /// Kept for existing callers: same as [useLocation].
  Future<void> allow() => useLocation();

  Future<void> _run(Future<CitySelection> Function()? obtainCity) async {
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
      if (obtainCity != null) {
        final city = await obtainCity();
        if (!current()) return;
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
      final message = switch (error) {
        DeviceLocationException e => e.message,
        CityPlacesException e => e.message,
        ApiError e => e.message,
        _ => 'Unable to get your location. Try again.',
      };
      emit(
        AllowLocationState(
          locationSaved: saved,
          openSettings: error is DeviceLocationException && error.openSettings,
          error: message,
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
