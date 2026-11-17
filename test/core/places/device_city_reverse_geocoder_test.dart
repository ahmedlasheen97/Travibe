import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/places/city_places_provider.dart';
import 'package:travibe/core/places/device_city_reverse_geocoder.dart';

class FakeSource implements DevicePlacemarkSource {
  FakeSource({this.available = true, this.places = const [], this.failure});
  bool available;
  List<DevicePlacemark> places;
  Object? failure;
  final calls = <String>[];

  @override
  Future<bool> isAvailable() async {
    calls.add('isAvailable');
    return available;
  }

  @override
  Future<List<DevicePlacemark>> placemarks(double lat, double lng) async {
    calls.add('placemarks $lat,$lng');
    if (failure != null) throw failure!;
    return places;
  }
}

class FakePhoton implements CityReverseGeocoder {
  final calls = <String>[];
  @override
  Future<CitySelection> reverse(double latitude, double longitude) async {
    calls.add('photon $latitude,$longitude');
    return CitySelection(
      cityName: 'Photon City',
      countryName: 'Egypt',
      countryCode: 'EG',
      latitude: latitude,
      longitude: longitude,
    );
  }
}

const cairo = DevicePlacemark(
  locality: 'Cairo',
  subAdministrativeArea: 'Cairo Governorate',
  administrativeArea: 'Cairo',
  country: 'Egypt',
  isoCountryCode: 'eg',
);

void main() {
  late FakeSource device;
  late FakePhoton photon;
  DeviceCityReverseGeocoder geocoder({bool isWeb = false}) =>
      DeviceCityReverseGeocoder(source: device, fallback: photon, isWeb: isWeb);

  setUp(() {
    device = FakeSource(places: const [cairo]);
    photon = FakePhoton();
  });

  test('uses the device geocoder by default, never Photon', () async {
    final city = await geocoder().reverse(30.04, 31.24);
    expect(city.cityName, 'Cairo');
    expect(city.countryName, 'Egypt');
    expect(city.countryCode, 'EG');
    expect(city.latitude, 30.04);
    expect(device.calls, ['isAvailable', 'placemarks 30.04,31.24']);
    expect(photon.calls, isEmpty);
  });

  test('falls back to the district name when locality is empty', () async {
    device.places = const [
      DevicePlacemark(
        locality: ' ',
        subAdministrativeArea: 'Giza',
        country: 'Egypt',
        isoCountryCode: 'EG',
      ),
    ];
    expect((await geocoder().reverse(30, 31)).cityName, 'Giza');
  });

  test('skips placemarks without a usable city or ISO country', () async {
    device.places = const [
      DevicePlacemark(country: 'Egypt', isoCountryCode: 'EG'),
      DevicePlacemark(locality: 'Nowhere', isoCountryCode: 'EGY'),
      cairo,
    ];
    expect((await geocoder().reverse(30, 31)).cityName, 'Cairo');
    expect(photon.calls, isEmpty);
  });

  test('web uses Photon and never touches the device plugin', () async {
    final city = await geocoder(isWeb: true).reverse(30.04, 31.24);
    expect(city.cityName, 'Photon City');
    expect(device.calls, isEmpty);
    expect(photon.calls, ['photon 30.04,31.24']);
  });

  test(
    'Android without Google Play services (no geocoder) uses Photon',
    () async {
      device.available = false;
      final city = await geocoder().reverse(30.04, 31.24);
      expect(city.cityName, 'Photon City');
      expect(device.calls, ['isAvailable']);
      expect(photon.calls, ['photon 30.04,31.24']);
    },
  );

  test('a platform error from the OS geocoder falls back to Photon', () async {
    device.failure = PlatformException(code: 'IO_ERROR');
    expect((await geocoder().reverse(30, 31)).cityName, 'Photon City');
    expect(photon.calls, hasLength(1));
  });

  test(
    'a missing plugin (unsupported platform) falls back to Photon',
    () async {
      device.failure = MissingPluginException();
      expect((await geocoder().reverse(30, 31)).cityName, 'Photon City');
    },
  );

  test('no usable device result falls back to Photon', () async {
    device.places = const [];
    expect((await geocoder().reverse(30, 31)).cityName, 'Photon City');
    expect(photon.calls, hasLength(1));
  });

  test('Photon failures still surface to the caller', () async {
    device.available = false;
    final failing = DeviceCityReverseGeocoder(
      source: device,
      fallback: _FailingPhoton(),
      isWeb: false,
    );
    expect(() => failing.reverse(30, 31), throwsA(isA<CityPlacesException>()));
  });
}

class _FailingPhoton implements CityReverseGeocoder {
  @override
  Future<CitySelection> reverse(double latitude, double longitude) =>
      Future.error(const CityPlacesException('No usable city'));
}
