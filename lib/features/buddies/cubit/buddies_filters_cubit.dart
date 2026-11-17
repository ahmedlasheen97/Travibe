import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import '../data/buddies_filters.dart';

/// Applied Buddies filters shared by In Your City, With Same Interests and
/// destination search. In memory only: they survive leaving and reopening
/// those screens and reset on login/logout.
class BuddiesFiltersCubit extends Cubit<BuddiesFilters> {
  BuddiesFiltersCubit({PreferencesManager? preferences})
    : _preferences = preferences ?? PreferencesManager(),
      super(BuddiesFilters()) {
    _session = _preferences.sessionRevision;
    _preferences.addListener(_sessionChanged);
  }
  final PreferencesManager _preferences;
  late int _session;

  void _sessionChanged() {
    if (_session == _preferences.sessionRevision) return;
    _session = _preferences.sessionRevision;
    if (!isClosed) emit(BuddiesFilters());
  }

  void apply(BuddiesFilters filters) {
    if (!isClosed && filters != state) emit(filters);
  }

  @override
  Future<void> close() {
    _preferences.removeListener(_sessionChanged);
    return super.close();
  }
}
