import 'dart:ui' as ui;
import 'package:travibe/features/profile/data/settings_repo.dart';
import 'package:travibe/features/profile/data/settings_update.dart';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:travibe/core/media/media_upload_service.dart';
import 'package:travibe/features/profile/data/profile_avatar_repo.dart';
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/core/places/city_places_provider.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/cubit/edit_profile_cubit.dart';
import 'package:travibe/features/profile/cubit/profile_cubit.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'package:travibe/features/profile/data/profile_repo.dart';
import 'package:travibe/features/profile/data/profile_update.dart';
import 'package:travibe/features/profile/screens/edit_profile_screen.dart';
import '../../core/places/fake_city_places.dart';
import 'fixtures.dart';
import 'edit_profile_test.dart' as editing;

class EditApi extends ApiService {
  final resource = <String, dynamic>{
    ...profileJson(),
    'nationality_code': 'EG',
    'current_location': 'Cairo, EG',
    'locale': 'en',
    'currency_code': 'AED',
    'show_active_status': true,
    'show_in_travel_buddy': false,
    'push_notifications_enabled': true,
  };
  final calls = <String>[];
  final patches = <Map<String, dynamic>>[];
  final locations = <Map<String, dynamic>>[];
  ApiError? patchError, locationError;
  Completer<void>? patchGate, locationGate;
  int failedReads = 0;
  bool failReadAfterPatch = false;
  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
    calls.add('GET $endpoint');
    if (failedReads > 0) {
      failedReads--;
      throw ApiError(message: 'Reload failed');
    }
    return {'data': Map.of(resource)};
  }

  @override
  Future<dynamic> patch(String endpoint, Map<String, dynamic> data) async {
    calls.add('PATCH $endpoint');
    patches.add(Map.of(data));
    if (patchGate != null) await patchGate!.future;
    if (patchError != null) throw patchError!;
    resource.addAll(data);
    if (failReadAfterPatch) failedReads++;
    return {'data': []}; // Ordinary PATCH resource is deliberately not assumed.
  }

  @override
  Future<dynamic> put(String endpoint, Map<String, dynamic> data) async {
    calls.add('PUT $endpoint');
    locations.add(Map.of(data));
    if (locationGate != null) await locationGate!.future;
    if (locationError != null) throw locationError!;
    resource['current_location'] = data['location'];
    return {'data': Map.of(resource)};
  }

  @override
  Future<dynamic> delete(String endpoint) async {
    calls.add('DELETE $endpoint');
    if (locationGate != null) await locationGate!.future;
    if (locationError != null) throw locationError!;
    resource['current_location'] = null;
    return null;
  }
}

class Photos extends ProfileAvatarRepo {
  @override
  Future<ProfileAvatarDraft?> pick() async => ProfileAvatarDraft(
    name: 'photo.png',
    bytes: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
  );
}

class Uploads extends MediaUploadService {
  int calls = 0;
  @override
  Future<int> upload({
    required String filename,
    required String contentType,
    required Uint8List bytes,
    required bool Function() isActive,
    required CancelToken cancelToken,
    required void Function(MediaUploadStage) onStage,
    void Function(int sent, int total)? onProgress,
  }) async {
    calls++;
    return 77;
  }
}

class PendingSettings extends SettingsRepo {
  final response = Completer<ProfileModel>();
  @override
  Future<ProfileModel> update(SettingsUpdate update) => response.future;
}

void main() {
  final preferences = PreferencesManager();
  final paris = testCity('Paris', code: 'FR', country: 'France');
  late EditApi api;
  late CurrentUserCubit user;
  late ProfileCubit owner;
  late FakeCityPlaces places;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.saveToken('edit-save-test');
    ScreenUtil.configure(
      data: const MediaQueryData(size: Size(390, 844)),
      designSize: const Size(390, 844),
      minTextAdapt: false,
      splitScreenMode: false,
    );
    api = EditApi();
    final repo = ProfileRepo(apiService: api);
    user = CurrentUserCubit(profileRepo: repo);
    await user.load();
    owner = ProfileCubit(profileRepo: repo, currentUser: user);
    await owner.loadProfile();
    api.calls.clear();
    places = FakeCityPlaces();
    places.onAutocomplete = (_) async => [
      CitySuggestion(id: 'paris', label: 'Paris, France', selection: paris),
    ];
    places.onResolve = (item) async => item.selection!;
  });
  tearDown(() async {
    await owner.close();
    await user.close();
    await preferences.clear();
  });
  ProfileModel getProfile() => (owner.state as ProfileLoaded).profile;
  Future<void> show(WidgetTester tester, {ProfileModel? initial}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepositoryProvider<CityPlacesProvider>.value(
        value: places,
        child: MaterialApp(
          theme: darkTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<bool>(
                    builder: (_) => EditProfileScreen(
                      profile: initial ?? getProfile(),
                      owner: owner,
                      selectionRepo: editing.SelectionRepo(),
                    ),
                  ),
                ),
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
  }

  Finder cityField() =>
      find.byKey(const ValueKey('edit-profile-current_location'));
  Finder save() => find.byType(ElevatedButton);
  bool enabled(WidgetTester tester) =>
      tester.widget<ElevatedButton>(save()).onPressed != null;
  Future<void> chooseParis(WidgetTester tester, {bool arrow = true}) async {
    await tester.ensureVisible(cityField());
    await tester.tap(
      arrow ? find.byTooltip('Choose current city') : find.text('Cairo, EG'),
    );
    await tester.pumpAndSettle();
    final input = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextField),
    );
    await tester.enterText(input, 'Par');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
  }

  test(
    'location draft is independent from PATCH and restoring the saved city removes dirtiness',
    () {
      final draft = ProfileDraft(getProfile());
      draft.selectCity(null);
      expect(draft.isDirty, true);
      expect(draft.hasLocationChange, true);
      expect(draft.changes, isEmpty);
      expect(draft.toUpdate().toJson(), isEmpty);
      draft.selectCity(testCity('Cairo', code: 'EG', country: 'Egypt'));
      expect(draft.isDirty, false);
      draft.selectCity(paris);
      expect(draft.currentLocation, 'Paris, FR');
      expect(draft.changes, isEmpty);
    },
  );
  test('acknowledging a city preserves a newer pending selection', () {
    final draft = ProfileDraft(getProfile())..selectCity(paris);
    draft.selectCity(null);
    draft.markLocationSaved(submitted: 'Paris, FR', canonical: 'Paris, FR');
    expect(draft.currentLocation, isNull);
    expect(draft.hasLocationChange, true);
  });
  testWidgets(
    'gender field and focused dropdown stay dark, preserve values and save only gender',
    (tester) async {
      api.resource['gender'] = 'female';
      await owner.loadProfile();
      api.calls.clear();
      await show(tester);
      final field = find.byKey(const ValueKey('edit-profile-gender'));
      await tester.scrollUntilVisible(
        field,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.getSize(field).height, 52);
      final dropdown = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: field,
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(dropdown.value, 'female');
      expect(dropdown.focusColor, DarkColors.darkgreyColor);
      expect(dropdown.dropdownColor, DarkColors.darkgreyColor);
      expect(dropdown.style!.color, DarkColors.whiteColor);
      expect((dropdown.icon as Icon).color, DarkColors.greyColor);
      expect(dropdown.items!.map((item) => item.value), [
        null,
        'male',
        'female',
        'other',
      ]);
      expect(enabled(tester), isFalse);
      await tester.tap(field);
      await tester.pumpAndSettle();
      // Flutter paints this popup with CustomPaint, not a colored Material.
      // Verify the actual popup painter's center pixel rather than its internals.
      final menu = find
          .ancestor(
            of: find.text('male').last,
            matching: find.byWidgetPredicate(
              (widget) => widget is CustomPaint && widget.painter != null,
            ),
          )
          .first;
      final painted = tester.widget<CustomPaint>(menu);
      final menuSize = tester.getSize(menu);
      final recorder = ui.PictureRecorder();
      painted.painter!.paint(Canvas(recorder), menuSize);
      final picture = recorder.endRecording();
      final image = picture.toImageSync(
        menuSize.width.toInt(),
        menuSize.height.toInt(),
      );
      final data = await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      final bytes = data!.buffer.asUint8List();
      final offset = ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
      expect(bytes.sublist(offset, offset + 4), [28, 28, 28, 255]);
      image.dispose();
      picture.dispose();
      await tester.tap(find.text('male').last);
      await tester.pumpAndSettle();
      final input = tester.widget<InputDecorator>(
        find.descendant(of: field, matching: find.byType(InputDecorator)),
      );
      expect(input.isFocused, isTrue);
      final decoration = input.decoration;
      expect(decoration.fillColor, DarkColors.darkgreyColor);
      expect(decoration.focusColor, DarkColors.darkgreyColor);
      expect(
        (decoration.focusedBorder! as OutlineInputBorder).borderSide,
        BorderSide.none,
      );
      expect(enabled(tester), isTrue);
      await tester.tap(save());
      await tester.pumpAndSettle();
      expect(api.patches, [
        {'gender': 'male'},
      ]);
      expect(api.locations, isEmpty);
      expect(
        api.calls.where((call) => call == 'DELETE profile/location'),
        isEmpty,
      );
      expect(getProfile().gender, 'male');
    },
  );

  testWidgets(
    'unspecified gender keeps muted hint and retains existing null mapping',
    (tester) async {
      api.resource['gender'] = 'female';
      await owner.loadProfile();
      await show(tester);
      final field = find.byKey(const ValueKey('edit-profile-gender'));
      await tester.scrollUntilVisible(
        field,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not specified').last);
      await tester.pumpAndSettle();
      expect(enabled(tester), isTrue);
      final hint = tester.widgetList<Text>(
        find.descendant(of: field, matching: find.text('Not specified')),
      );
      expect(
        hint.any((text) => text.style?.color == DarkColors.greyColor),
        isTrue,
      );
      await tester.tap(save());
      await tester.pumpAndSettle();
      // Clearing an existing required detail retains the existing confirmation.
      if (find.text('Clear and Save').evaluate().isNotEmpty) {
        await tester.tap(find.text('Clear and Save'));
        await tester.pumpAndSettle();
      }
      expect(api.patches, [
        {'gender': null},
      ]);
    },
  );

  testWidgets(
    'inline X precedes arrow; clearing stays pending without picker or DELETE',
    (tester) async {
      await show(tester);
      await tester.ensureVisible(cityField());
      final before = tester.getRect(cityField());
      expect(before.height, 52);
      expect(
        find.widgetWithText(TextButton, 'Clear current city'),
        findsNothing,
      );
      expect(
        tester.getCenter(find.byTooltip('Clear current city')).dx,
        lessThan(tester.getCenter(find.byTooltip('Choose current city')).dx),
      );
      expect(enabled(tester), false);
      await tester.tap(find.byTooltip('Clear current city'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byTooltip('Clear current city'), findsNothing);
      expect(api.calls, isEmpty);
      expect(enabled(tester), true);
      expect(getProfile().currentLocation, 'Cairo, EG');
      expect(tester.getRect(cityField()).height, before.height);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('empty city has no X and no extra clear-button spacing', (
    tester,
  ) async {
    api.resource['current_location'] = null;
    await user.load();
    await owner.refresh();
    api.calls.clear();
    await show(tester);
    await tester.ensureVisible(cityField());
    expect(find.byTooltip('Clear current city'), findsNothing);
    expect(tester.getSize(cityField()).height, 52);
    expect(enabled(tester), false);
    await tester.pumpWidget(const SizedBox());
  });
  for (final arrow in [true, false]) {
    testWidgets(
      '${arrow ? 'Arrow' : 'Field'} opens picker, selection enables Save without immediate PUT',
      (tester) async {
        await show(tester);
        await chooseParis(tester, arrow: arrow);
        expect(find.text('Paris, FR'), findsOneWidget);
        expect(find.byTooltip('Clear current city'), findsOneWidget);
        expect(enabled(tester), true);
        expect(api.calls, isEmpty);
        expect(getProfile().currentLocation, 'Cairo, EG');
        await tester.tap(find.text('Save Changes'));
        await tester.pumpAndSettle();
        expect(api.calls, ['PUT profile/location']);
        expect(api.locations.single, {'location': 'Paris, FR'});
        expect(api.patches, isEmpty);
        expect(getProfile().currentLocation, 'Paris, FR');
        expect(user.state.profile!.currentLocation, 'Paris, FR');
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'opening then cancelling the picker does not dirty or clear a saved city',
    (tester) async {
      await show(tester);
      await tester.ensureVisible(cityField());
      await tester.tap(find.byTooltip('Choose current city'));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();
      expect(find.text('Cairo, EG'), findsOneWidget);
      expect(enabled(tester), false);
      expect(api.calls, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('clear is cancelled by discarding the form without DELETE', (
    tester,
  ) async {
    await show(tester);
    await tester.ensureVisible(cityField());
    await tester.tap(find.byTooltip('Clear current city'));
    await tester.pumpAndSettle();
    final state = tester.state<NavigatorState>(find.byType(Navigator));
    await state.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Discard Changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Open editor'), findsOneWidget);
    expect(api.calls, isEmpty);
    expect(getProfile().currentLocation, 'Cairo, EG');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Save clearing invokes DELETE only, then removes the canonical city',
    (tester) async {
      await show(tester);
      await tester.ensureVisible(cityField());
      await tester.tap(find.byTooltip('Clear current city'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(api.calls, ['DELETE profile/location']);
      expect(api.patches, isEmpty);
      expect(getProfile().currentLocation, isNull);
      expect(user.state.profile!.currentLocation, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final entry in {
    'full_name': 'New name',
    'username': 'new_name',
    'bio': 'New bio',
  }.entries) {
    testWidgets(
      'editing ${entry.key} enables Save and synchronizes profile state',
      (tester) async {
        await show(tester);
        final field = find.byKey(ValueKey(entry.key));
        await tester.scrollUntilVisible(
          field,
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.enterText(field, entry.value);
        await tester.pumpAndSettle();
        expect(enabled(tester), true);
        await tester.tap(find.text('Save Changes'));
        await tester.pumpAndSettle();
        expect(api.patches.single, {entry.key: entry.value});
        final profile = getProfile();
        expect(switch (entry.key) {
          'full_name' => profile.name,
          'username' => profile.username,
          _ => profile.bio,
        }, entry.value);
        expect(switch (entry.key) {
          'full_name' => user.state.profile!.name,
          'username' => user.state.profile!.username,
          _ => user.state.profile!.bio,
        }, entry.value);
        await tester.tap(find.text('Open editor'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextFormField>(find.byKey(ValueKey(entry.key)))
              .controller!
              .text,
          entry.value,
        );
        expect(enabled(tester), false);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('changing nationality enables Save with nationality_code only', (
    tester,
  ) async {
    await show(tester);
    final field = find.byKey(const ValueKey('edit-profile-nationality_code'));
    await tester.scrollUntilVisible(
      field,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(TextField),
      ),
      'France',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('France').last);
    await tester.pumpAndSettle();
    expect(enabled(tester), true);
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(api.patches.single, {'nationality_code': 'FR'});
    expect(getProfile().nationalityCode, 'FR');
    await tester.pumpWidget(const SizedBox());
  });
  for (final entry in {
    'full_name': '  ',
    'username': 'ab',
    'bio': 'a' * 181,
  }.entries) {
    testWidgets('invalid ${entry.key} cannot submit', (tester) async {
      await show(tester);
      final field = find.byKey(ValueKey(entry.key));
      await tester.scrollUntilVisible(
        field,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      // Bio is length-limited by its existing field; set a supplied overlong draft
      // through its callback to exercise validation independently of the keyboard.
      if (entry.key == 'bio') {
        tester.widget<TextFormField>(field).onChanged!(entry.value);
      } else {
        await tester.enterText(field, entry.value);
      }
      await tester.pumpAndSettle();
      expect(enabled(tester), false);
      expect(api.patches, isEmpty);
      expect(api.locations, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'owner canonical values override a stale navigation snapshot at initialization',
    (tester) async {
      final stale = getProfile();
      api.resource['full_name'] = 'Canonical name';
      api.resource['username'] = 'canonical';
      api.resource['bio'] = 'Canonical bio';
      await owner.refresh();
      await show(tester, initial: stale);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('full_name')))
            .controller!
            .text,
        'Canonical name',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('username')))
            .controller!
            .text,
        'canonical',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('bio')))
            .controller!
            .text,
        'Canonical bio',
      );
      expect(enabled(tester), false);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'saving displays one white Cupertino loader and prevents duplicate city requests',
    (tester) async {
      await show(tester);
      await chooseParis(tester);
      api.locationGate = Completer<void>();
      await tester.tap(find.text('Save Changes'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        tester
            .widget<CupertinoActivityIndicator>(
              find.byType(CupertinoActivityIndicator),
            )
            .color,
        DarkColors.whiteColor,
      );
      expect(tester.widget<ElevatedButton>(save()).onPressed, isNull);
      expect(api.calls, ['PUT profile/location']);
      api.locationGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'ordinary PATCH succeeds before location; retry does not resubmit successful fields',
    () async {
      final editor = EditProfileCubit(owner);
      final draft = ProfileDraft(getProfile())
        ..set('full_name', 'Saved name')
        ..selectCity(paris);
      api.locationError = ApiError(message: 'City failed', statusCode: 422);
      expect(await editor.save(draft), false);
      expect(api.calls, [
        'PATCH profile',
        'GET profile',
        'PUT profile/location',
      ]);
      expect(draft.changes, isEmpty);
      expect(draft.hasLocationChange, true);
      expect(getProfile().name, 'Saved name');
      expect(user.state.profile!.name, 'Saved name');
      expect(
        editor.state.error!.fieldErrors.containsKey('current_location'),
        true,
      );
      api.calls.clear();
      api.locationError = null;
      expect(await editor.save(draft), true);
      expect(api.calls, ['PUT profile/location']);
      expect(draft.isDirty, false);
      await editor.close();
    },
  );
  test(
    'failed ordinary PATCH keeps both operations pending and never writes location',
    () async {
      final editor = EditProfileCubit(owner);
      final draft = ProfileDraft(getProfile())
        ..set('bio', 'Pending bio')
        ..selectCity(paris);
      api.patchError = ApiError(message: 'Invalid bio', statusCode: 422);
      expect(await editor.save(draft), false);
      expect(api.calls, ['PATCH profile']);
      expect(draft.changes, {'bio': 'Pending bio'});
      expect(draft.hasLocationChange, true);
      api.patchError = null;
      expect(await editor.save(draft), true);
      expect(api.calls.last, 'PUT profile/location');
      expect(draft.isDirty, false);
      await editor.close();
    },
  );
  test(
    'failed DELETE retains a pending clear and retries DELETE only',
    () async {
      final editor = EditProfileCubit(owner);
      final draft = ProfileDraft(getProfile())..selectCity(null);
      api.locationError = ApiError(message: 'Offline');
      expect(await editor.save(draft), false);
      expect(draft.hasLocationChange, true);
      expect(getProfile().currentLocation, 'Cairo, EG');
      api.locationError = null;
      expect(await editor.save(draft), true);
      expect(api.calls, ['DELETE profile/location', 'DELETE profile/location']);
      expect(draft.isDirty, false);
      await editor.close();
    },
  );
  test(
    'refresh failure after PATCH does not replay that PATCH when saving the pending city',
    () async {
      final editor = EditProfileCubit(owner);
      final draft = ProfileDraft(getProfile())
        ..set('username', 'saved_name')
        ..selectCity(paris);
      api.failReadAfterPatch = true;
      expect(await editor.save(draft), false);
      expect(api.patches, hasLength(1));
      expect(api.locations, isEmpty);
      expect(draft.changes, isEmpty);
      expect(draft.hasLocationChange, true);
      expect(await editor.save(draft), true);
      expect(api.patches, hasLength(1));
      expect(api.locations, hasLength(1));
      expect(getProfile().username, 'saved_name');
      await editor.close();
    },
  );
  test('duplicate saving taps cannot send duplicate PUT', () async {
    final editor = EditProfileCubit(owner);
    final draft = ProfileDraft(getProfile())..selectCity(paris);
    api.locationGate = Completer<void>();
    final pending = editor.save(draft);
    expect(await editor.save(draft), false);
    expect(api.locations, hasLength(1));
    api.locationGate!.complete();
    expect(await pending, true);
    await editor.close();
  });
  test(
    'account switch ignores a late location response and retains no old profile',
    () async {
      final editor = EditProfileCubit(owner);
      final draft = ProfileDraft(getProfile())..selectCity(paris);
      api.locationGate = Completer<void>();
      final pending = editor.save(draft);
      await preferences.clear();
      api.locationGate!.complete();
      expect(await pending, false);
      expect(editor.state.sessionChanged, true);
      expect(user.state.profile, isNull);
      expect(owner.state, isA<ProfileInitial>());
      await editor.close();
    },
  );
  testWidgets(
    'partial failure keeps pending city visible and enables a useful retry',
    (tester) async {
      await show(tester);
      await tester.enterText(
        find.byKey(const ValueKey('full_name')),
        'Saved name',
      );
      await chooseParis(tester);
      api.locationError = ApiError(message: 'City failed', statusCode: 422);
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsOneWidget);
      expect(find.text('Paris, FR'), findsOneWidget);
      expect(enabled(tester), true);
      expect(api.patches, hasLength(1));
      expect(find.textContaining('City failed'), findsWidgets);
      api.locationError = null;
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(api.patches, hasLength(1));
      expect(api.locations, hasLength(2));
      expect(find.text('Open editor'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'uploaded avatar and committed PATCH are not repeated after location fails',
    () async {
      final uploads = Uploads();
      final editor = EditProfileCubit(
        owner,
        avatarRepo: Photos(),
        mediaUpload: uploads,
      );
      await editor.pickAvatar();
      final draft = ProfileDraft(getProfile())..selectCity(paris);
      api.locationError = ApiError(message: 'City failed');
      expect(await editor.save(draft), false);
      expect(uploads.calls, 1);
      expect(api.patches.single, {'avatar_media_id': 77});
      expect(editor.state.avatar, isNull);
      api.locationError = null;
      expect(await editor.save(draft), true);
      expect(uploads.calls, 1);
      expect(api.patches, hasLength(1));
      await editor.close();
      uploads.close();
    },
  );
  test(
    'later city edits remain pending when an older location write completes',
    () async {
      final editor = EditProfileCubit(owner);
      final draft = ProfileDraft(getProfile())..selectCity(paris);
      api.locationGate = Completer<void>();
      final save = editor.save(draft);
      draft.selectCity(null);
      api.locationGate!.complete();
      expect(await save, false);
      expect(editor.state.saved, false);
      expect(draft.currentLocation, isNull);
      expect(draft.hasLocationChange, true);
      expect(getProfile().currentLocation, 'Paris, FR');
      api.locationGate = null;
      expect(await editor.save(draft), true);
      expect(api.calls.last, 'DELETE profile/location');
      await editor.close();
    },
  );
  testWidgets('a city-only edit does not validate an unrelated absent name', (
    tester,
  ) async {
    api.resource['name'] = '';
    await owner.refresh();
    api.calls.clear();
    await show(tester);
    await chooseParis(tester);
    expect(enabled(tester), true);
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(api.patches, isEmpty);
    expect(api.locations.single, {'location': 'Paris, FR'});
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'a delayed settings response cannot overwrite a newer profile edit',
    () async {
      final settings = PendingSettings();
      final repo = ProfileRepo(apiService: api);
      final shared = CurrentUserCubit(
        profileRepo: repo,
        settingsRepo: settings,
      );
      await shared.load();
      final profile = ProfileCubit(profileRepo: repo, currentUser: shared);
      await profile.loadProfile();
      final older = ProfileModel.fromJson({
        ...api.resource,
        'show_active_status': false,
      });
      final pending = shared.update(
        SettingsUpdate({'show_active_status': false}),
      );
      await profile.updateMyProfile(
        ProfileUpdate({'full_name': 'Newest name'}),
        expectedId: '7',
      );
      expect(shared.state.profile!.name, 'Newest name');
      settings.response.complete(older);
      await pending;
      expect(shared.state.profile!.name, 'Newest name');
      expect(shared.state.profile!.showActiveStatus, false);
      expect((profile.state as ProfileLoaded).profile.name, 'Newest name');
      await profile.close();
      await shared.close();
    },
  );
  testWidgets(
    'cancelling the required-details confirmation restores the enabled Save button',
    (tester) async {
      await show(tester);
      await tester.enterText(find.byKey(const ValueKey('username')), '');
      await tester.pumpAndSettle();
      expect(enabled(tester), true);
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(find.text('Clear profile details?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(enabled(tester), true);
      expect(api.patches, isEmpty);
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear and Save'));
      await tester.pumpAndSettle();
      expect(api.patches.single, {'username': null});
      await tester.pumpWidget(const SizedBox());
    },
  );
}
