import 'package:country_picker/country_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/reference/nationality_labels.dart';

void main() {
  test('every country has a nationality word (demonym)', () {
    final missing = [
      for (final country in CountryService().getAll())
        if (!nationalityDemonyms.containsKey(country.countryCode))
          country.countryCode,
    ];
    expect(missing, isEmpty);
    expect(
      nationalityDemonyms.values.where((value) => value.trim().isEmpty),
      isEmpty,
    );
  });

  test('labels use the demonym, not the country name', () {
    expect(nationalityLabel('EG', countryName: 'Egypt'), 'Egyptian');
    expect(nationalityLabel('NZ', countryName: 'New Zealand'), 'New Zealander');
    expect(nationalityLabel('PH', countryName: 'Philippines'), 'Filipino');
  });
}
