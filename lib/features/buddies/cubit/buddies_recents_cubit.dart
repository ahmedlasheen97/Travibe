import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import '../data/buddies_repo.dart';
import '../data/recent_destination.dart';

/// The signed-in account's recent Buddies destinations, kept on the server
/// (`buddies/search/recent`). Newest first, at most [max], unique ignoring case.
class BuddiesRecentsCubit extends Cubit<List<RecentDestination>> {
  BuddiesRecentsCubit({BuddiesRepo? repo})
    : _repo = repo ?? BuddiesRepo(),
      super(const []) {
    _preferences.addListener(_sessionChanged);
  }

  static const max = 10;
  final BuddiesRepo _repo;
  final _preferences = PreferencesManager();
  int _generation = 0;

  bool _current(int generation, int session) =>
      !isClosed &&
      generation == _generation &&
      session == _preferences.sessionRevision;

  void _sessionChanged() {
    if (isClosed) return;
    ++_generation;
    emit(const []);
    if (_preferences.hasSession) load();
  }

  Future<void> load() async {
    if (isClosed || !_preferences.hasSession) return;
    final generation = ++_generation;
    final session = _preferences.sessionRevision;
    try {
      final items = await _repo.getRecentDestinations();
      if (_current(generation, session)) emit(_normalize(items));
    } catch (_) {
      // History is optional; search keeps working without it.
    }
  }

  /// Applies a destination the server just stored.
  void saved(RecentDestination item, {required int session}) {
    if (isClosed || session != _preferences.sessionRevision) return;
    ++_generation; // a slower load must not overwrite the newer list
    emit(_normalize([item, ...state]));
  }

  Future<void> remove(RecentDestination item) => _mutate(
    state.where((other) => other.id != item.id).toList(),
    () => _repo.deleteRecentDestination(item.id),
  );

  Future<void> clear() => _mutate(const [], _repo.clearRecentDestinations);

  /// Updates the list immediately and restores it if the request fails.
  Future<void> _mutate(
    List<RecentDestination> next,
    Future<void> Function() request,
  ) async {
    if (isClosed) return;
    final previous = state;
    final generation = ++_generation;
    final session = _preferences.sessionRevision;
    emit(next);
    try {
      await request();
    } catch (_) {
      if (_current(generation, session)) emit(previous);
    }
  }

  static List<RecentDestination> _normalize(List<RecentDestination> items) {
    final result = <RecentDestination>[];
    for (final item in items) {
      if (result.any((other) => other.sameDestination(item.destination))) {
        continue;
      }
      result.add(item);
      if (result.length == max) break;
    }
    return result;
  }

  @override
  Future<void> close() {
    ++_generation;
    _preferences.removeListener(_sessionChanged);
    return super.close();
  }
}
