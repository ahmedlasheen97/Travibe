import 'package:travibe/core/places/city_places_provider.dart';

CitySelection testCity(
  String text, {
  String code = 'ID',
  String country = 'Indonesia',
}) => CitySelection(
  cityName: text.split(',').first,
  countryName: country,
  countryCode: code,
  latitude: 0,
  longitude: 0,
);

class FakeCityPlaces implements CityPlacesProvider {
  int calls = 0, detailsCalls = 0;
  final List<String> inputs = [];
  Future<List<CitySuggestion>> Function(String)? onAutocomplete;
  Future<CitySelection> Function(CitySuggestion)? onResolve;
  @override
  Future<List<CitySuggestion>> autocomplete(String input) async {
    calls++;
    inputs.add(input);
    if (onAutocomplete != null) return onAutocomplete!(input);
    return [CitySuggestion(id: input, label: '$input, Indonesia')];
  }

  @override
  Future<CitySelection> resolve(CitySuggestion suggestion) async {
    detailsCalls++;
    if (onResolve != null) return onResolve!(suggestion);
    return testCity(suggestion.id);
  }
}
