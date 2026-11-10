import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import '../data/buddies_home_response.dart';
import '../data/buddies_repo.dart';
import 'dart:async';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';

class BuddiesState {
  const BuddiesState({this.home, this.loading = false, this.error});
  final BuddiesHomeResponse? home;
  final bool loading;
  final ApiError? error;
}

class BuddiesCubit extends Cubit<BuddiesState> {
  BuddiesCubit({
    BuddiesRepo? repo,
    PreferencesManager? preferences,
    CurrentUserCubit? currentUser,
  }) : _repo = repo ?? BuddiesRepo(),
       _preferences = preferences ?? PreferencesManager(),
       _currentUser = currentUser,
       super(const BuddiesState()) {
    _location = currentUser?.state.profile?.currentLocation;
    _preferences.addListener(_sessionChanged);
    _userSubscription = currentUser?.stream.listen((user) {
      if (user.saving != null || user.loading) return;
      final location = user.profile?.currentLocation;
      final locationChanged = location != _location;
      _location = location;
      final visible = user.profile?.showInTravelBuddy;
      if (isClosed ||
          (!locationChanged &&
              (visible == null ||
                  visible == state.home?.meta.showInTravelBuddy))) {
        return;
      }
      ++_generation;
      _pending = null;
      var home = state.home?.withVisibility(visible);
      if (user.profile?.locationIncluded == true && locationChanged) {
        home = home?.withLocation(location, invalidateCity: true);
      }
      emit(BuddiesState(home: home));
      load(userInitiated: false);
    });
  }
  String? _location;
  final CurrentUserCubit? _currentUser;
  StreamSubscription<CurrentUserState>? _userSubscription;
  final BuddiesRepo _repo;
  final PreferencesManager _preferences;
  int _generation = 0;
  Future<void>? _pending;

  void _sessionChanged() {
    ++_generation;
    _pending = null;
    emit(const BuddiesState());
    load();
  }

  Future<void> load({bool userInitiated = true}) {
    if (isClosed) return Future.value();
    if (_pending != null) {
      if (userInitiated && !state.loading) {
        emit(BuddiesState(home: state.home, loading: true));
      }
      return _pending!;
    }
    if (!_preferences.hasSession) {
      emit(
        BuddiesState(
          error: ApiError(
            message: 'Sign in to discover travelers.',
            statusCode: 401,
          ),
        ),
      );
      return Future.value();
    }
    final generation = ++_generation;
    final session = _preferences.sessionRevision;
    emit(
      BuddiesState(
        home: state.home,
        loading: userInitiated || state.home == null,
      ),
    );
    final request = _load(generation, session);
    _pending = request;
    return request.whenComplete(() {
      if (generation == _generation) _pending = null;
    });
  }

  Future<void> _load(int generation, int session) async {
    bool current() =>
        !isClosed &&
        generation == _generation &&
        session == _preferences.sessionRevision;
    try {
      var home = await _repo.getHome();
      if (current()) {
        if (_currentUser?.state.profile?.locationIncluded == true) {
          home = home.withLocation(
            _currentUser!.state.profile!.currentLocation,
          );
        }
        emit(
          BuddiesState(
            home: home.withVisibility(
              _currentUser?.state.profile?.showInTravelBuddy,
            ),
          ),
        );
      }
    } catch (error) {
      if (!current()) return;
      final failure = error is ApiError
          ? error
          : ApiError(message: 'Unable to load travelers. Please try again.');
      emit(
        BuddiesState(
          home: [401, 403].contains(failure.statusCode) ? null : state.home,
          error: failure,
        ),
      );
    }
  }

  @override
  Future<void> close() {
    _userSubscription?.cancel();
    _preferences.removeListener(_sessionChanged);
    ++_generation;
    return super.close();
  }
}
