import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'city_places_provider.dart';
import 'photon_city_places_provider.dart';

class CityAutocompleteState {
  const CityAutocompleteState({
    this.text = '',
    this.suggestions = const [],
    this.selected,
    this.loading = false,
    this.debouncing = false,
    this.resolving = false,
    this.error,
    this.searched = false,
  });
  final String text;
  final List<CitySuggestion> suggestions;
  final CitySelection? selected;
  final bool loading, debouncing, resolving, searched;
  final String? error;
}

/// Reusable city entry state. No profile writes, location permissions or caches.
class CityAutocompleteCubit extends Cubit<CityAutocompleteState> {
  CityAutocompleteCubit({
    CityPlacesProvider? provider,
    this.debounce = const Duration(milliseconds: 350),
  }) : _provider = provider ?? PhotonCityPlacesProvider(),
       super(const CityAutocompleteState()) {
    _preferences.addListener(_sessionChanged);
  }
  final CityPlacesProvider _provider;
  final Duration debounce;
  final _preferences = PreferencesManager();
  Timer? _timer;
  int _generation = 0;
  void _sessionChanged() => clear();
  bool _current(int generation, int session) =>
      !isClosed &&
      generation == _generation &&
      session == _preferences.sessionRevision;

  void setText(String text) {
    if (isClosed || text == state.text) return;
    _timer?.cancel();
    ++_generation;
    if (text.trim().runes.length < 2 || text.runes.length > 120) {
      emit(CityAutocompleteState(text: text));
      return;
    }
    emit(CityAutocompleteState(text: text, debouncing: true));
    _timer = Timer(debounce, retry);
  }

  Future<void> retry() async {
    if (isClosed ||
        state.loading ||
        state.resolving ||
        state.selected != null ||
        state.text.trim().runes.length < 2 ||
        state.text.runes.length > 120) {
      return;
    }
    _timer?.cancel();
    final generation = ++_generation;
    final session = _preferences.sessionRevision;
    final text = state.text;
    if (!_preferences.hasSession) {
      emit(
        CityAutocompleteState(text: text, error: 'Sign in to choose a city.'),
      );
      return;
    }
    emit(CityAutocompleteState(text: text, loading: true));
    try {
      final suggestions = await _provider.autocomplete(text.trim());
      if (!_current(generation, session)) return;
      emit(
        CityAutocompleteState(
          text: text,
          suggestions: List.unmodifiable(suggestions),
          searched: true,
        ),
      );
    } catch (error, stack) {
      if (!_current(generation, session)) return;
      if (error is! CityPlacesException) addError(error, stack);
      emit(
        CityAutocompleteState(
          text: text,
          error: error is CityPlacesException
              ? error.message
              : 'Unable to load city suggestions. Try again.',
        ),
      );
    }
  }

  Future<void> select(CitySuggestion suggestion) async {
    if (isClosed ||
        state.resolving ||
        !state.suggestions.contains(suggestion)) {
      return;
    }
    _timer?.cancel();
    final generation = ++_generation;
    final session = _preferences.sessionRevision;
    final text = state.text;
    emit(CityAutocompleteState(text: text, resolving: true));
    try {
      final selected = await _provider.resolve(suggestion);
      if (!_current(generation, session)) return;
      emit(CityAutocompleteState(text: selected.label, selected: selected));
    } catch (error, stack) {
      if (!_current(generation, session)) return;
      if (error is! CityPlacesException) addError(error, stack);
      emit(
        CityAutocompleteState(
          text: text,
          error: error is CityPlacesException
              ? error.message
              : 'Unable to confirm this city. Choose a city again.',
        ),
      );
    }
  }

  void clear() {
    if (isClosed) return;
    _timer?.cancel();
    ++_generation;
    emit(const CityAutocompleteState());
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    ++_generation;
    _preferences.removeListener(_sessionChanged);
    return super.close();
  }
}
