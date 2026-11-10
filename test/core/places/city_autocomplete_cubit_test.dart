import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/places/city_autocomplete_cubit.dart';
import 'package:travibe/core/places/city_places_provider.dart';
import 'fake_city_places.dart';

class _ErrorObserver extends BlocObserver {
  final errors = <Object>[];
  @override
  void onError(BlocBase bloc, Object error, StackTrace stackTrace) {
    errors.add(error);
    super.onError(bloc, error, stackTrace);
  }
}

void main() {
  final preferences = PreferencesManager();
  late FakeCityPlaces provider;
  late CityAutocompleteCubit cubit;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.saveToken('account-A');
    provider = FakeCityPlaces();
    cubit = CityAutocompleteCubit(provider: provider);
  });
  tearDown(() async {
    await cubit.close();
    await preferences.clear();
  });

  testWidgets(
    '2-character threshold and 350ms debounce make only the latest call',
    (tester) async {
      cubit.setText('L');
      await tester.pump(const Duration(milliseconds: 400));
      expect(provider.calls, 0);
      cubit.setText('Lo');
      await tester.pump(const Duration(milliseconds: 200));
      cubit.setText('Lon');
      await tester.pump(const Duration(milliseconds: 349));
      expect(provider.calls, 0);
      await tester.pump(const Duration(milliseconds: 1));
      expect(provider.inputs, ['Lon']);
      expect(cubit.state.suggestions.single.id, 'Lon');
    },
  );

  for (final fails in [false, true]) {
    testWidgets(
      'rapid typing ignores stale ${fails ? 'failure' : 'success'} before next debounce',
      (tester) async {
        final pending = Completer<List<CitySuggestion>>();
        provider.onAutocomplete = (_) => pending.future;
        cubit.setText('Lon');
        await tester.pump(const Duration(milliseconds: 350));
        expect(cubit.state.loading, true);
        cubit.setText('Par');
        if (fails) {
          pending.completeError(const CityPlacesException('Old error'));
        } else {
          pending.complete([
            const CitySuggestion(id: 'old', label: 'Old city'),
          ]);
        }
        await tester.pump();
        expect(cubit.state.suggestions, isEmpty);
        expect(cubit.state.error, isNull);
        provider.onAutocomplete = null;
        await tester.pump(const Duration(milliseconds: 350));
        expect(cubit.state.suggestions.single.id, 'Par');
      },
    );
  }

  test(
    'selection retains structured fields without an additional network search',
    () async {
      cubit.setText('Lon');
      await cubit.retry();
      await cubit.select(cubit.state.suggestions.single);
      expect(provider.calls, 1);
      expect(cubit.state.selected!.countryCode, 'ID');
      expect(cubit.state.selected!.latitude, 0);
      expect(cubit.state.text, 'Lon, Indonesia');
      expect(cubit.state.suggestions, isEmpty);
    },
  );
  test('clear removes selection and discards pending resolution', () async {
    cubit.setText('Lon');
    await cubit.retry();
    final details = Completer<CitySelection>();
    provider.onResolve = (_) => details.future;
    final request = cubit.select(cubit.state.suggestions.single);
    cubit.clear();
    details.complete(
      CitySelection(
        cityName: 'London',
        countryName: 'Canada',
        countryCode: 'CA',
        latitude: 0,
        longitude: 0,
      ),
    );
    await request;
    expect(cubit.state.text, '');
    expect(cubit.state.selected, isNull);
    cubit.setText('Par');
    await cubit.retry();
  });
  test('editing while resolution is pending discards its selection', () async {
    cubit.setText('Lon');
    await cubit.retry();
    final details = Completer<CitySelection>();
    provider.onResolve = (_) => details.future;
    final request = cubit.select(cubit.state.suggestions.single);
    cubit.setText('Par');
    details.complete(
      CitySelection(
        cityName: 'London',
        countryName: 'Canada',
        countryCode: 'CA',
        latitude: 0,
        longitude: 0,
      ),
    );
    await request;
    expect(cubit.state.selected, isNull);
    expect(cubit.state.text, 'Par');
  });
  test('failed resolution permits fresh autocomplete on retry', () async {
    cubit.setText('Lon');
    await cubit.retry();
    provider.onResolve = (_) async =>
        throw const CityPlacesException('No country');
    await cubit.select(cubit.state.suggestions.single);
    expect(cubit.state.error, 'No country');
    expect(cubit.state.selected, isNull);
    await cubit.retry();
    expect(provider.calls, 2);
  });
  test('duplicate selection and retry requests are suppressed', () async {
    final suggestions = Completer<List<CitySuggestion>>();
    provider.onAutocomplete = (_) => suggestions.future;
    cubit.setText('Lon');
    final request = cubit.retry();
    await cubit.retry();
    expect(provider.calls, 1);
    suggestions.complete([
      const CitySuggestion(id: 'Lon', label: 'London, Canada'),
    ]);
    await request;
    final suggestion = cubit.state.suggestions.single;
    final details = Completer<CitySelection>();
    provider.onResolve = (_) => details.future;
    final resolving = cubit.select(suggestion);
    await cubit.select(suggestion);
    expect(provider.detailsCalls, 1);
    details.complete(
      CitySelection(
        cityName: 'London',
        countryName: 'Canada',
        countryCode: 'CA',
        latitude: 0,
        longitude: 0,
      ),
    );
    await resolving;
  });
  test('empty/error/retry states and over-limit input are explicit', () async {
    provider.onAutocomplete = (_) async => [];
    cubit.setText('zz');
    await cubit.retry();
    expect(cubit.state.searched, true);
    expect(cubit.state.suggestions, isEmpty);
    provider.onAutocomplete = (_) async =>
        throw const CityPlacesException('Offline');
    await cubit.retry();
    expect(cubit.state.error, 'Offline');
    provider.onAutocomplete = null;
    await cubit.retry();
    expect(cubit.state.error, isNull);
    final calls = provider.calls;
    cubit.setText('x' * 121);
    await cubit.retry();
    expect(provider.calls, calls);
  });
  test(
    'unexpected programming errors are observed and loading always resets',
    () async {
      final original = Bloc.observer;
      final observer = _ErrorObserver();
      Bloc.observer = observer;
      addTearDown(() => Bloc.observer = original);
      await cubit.close();
      cubit = CityAutocompleteCubit(provider: provider);
      provider.onAutocomplete = (_) async => throw StateError('provider bug');
      cubit.setText('cai');
      await cubit.retry();
      expect(observer.errors.single, isA<StateError>());
      expect(cubit.state.loading, false);
      expect(cubit.state.debouncing, false);
      expect(cubit.state.error, isNotNull);
      expect(cubit.state.searched, false);
      provider.onAutocomplete = null;
      await cubit.retry();
      expect(cubit.state.error, isNull);
      expect(cubit.state.suggestions, isNotEmpty);
    },
  );
  testWidgets(
    'session switch discards pending suggestions and cancels debounce',
    (tester) async {
      final pending = Completer<List<CitySuggestion>>();
      provider.onAutocomplete = (_) => pending.future;
      cubit.setText('Lon');
      final request = cubit.retry();
      await preferences.saveToken('account-B');
      pending.complete([
        const CitySuggestion(id: 'Lon', label: 'London, Canada'),
      ]);
      await request;
      expect(cubit.state.text, '');
      expect(cubit.state.suggestions, isEmpty);
      cubit.setText('Par');
      await preferences.clear();
      await tester.pump(const Duration(milliseconds: 400));
      expect(provider.calls, 1);
    },
  );
  test('logout while resolving cannot restore selected city', () async {
    cubit.setText('Lon');
    await cubit.retry();
    final details = Completer<CitySelection>();
    provider.onResolve = (_) => details.future;
    final request = cubit.select(cubit.state.suggestions.single);
    await preferences.clear();
    details.complete(
      CitySelection(
        cityName: 'London',
        countryName: 'Canada',
        countryCode: 'CA',
        latitude: 0,
        longitude: 0,
      ),
    );
    await request;
    expect(cubit.state.selected, isNull);
  });
  test('disposal cancels debounce and ignores pending responses', () async {
    cubit.setText('Lon');
    await cubit.close();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(provider.calls, 0);
  });
}
