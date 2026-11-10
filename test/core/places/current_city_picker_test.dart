import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/places/city_autocomplete_results.dart';
import 'package:travibe/core/places/city_places_provider.dart';
import 'package:travibe/core/places/current_city_picker.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/cubit/profile_cubit.dart';
import 'package:travibe/features/profile/data/profile_repo.dart';
import 'package:travibe/features/profile/screens/edit_profile_screen.dart';
import 'package:travibe/features/profilesetup/cubit/profile_setup_cubit.dart';
import 'package:travibe/features/profilesetup/data/profile_setup_repo.dart';
import 'package:travibe/features/profilesetup/widgets/step1_basic_info.dart';
import '../../features/buddies/buddies_backend_integration_test.dart'
    as backend;
import '../../features/profile/edit_profile_test.dart' as editing;
import 'fake_city_places.dart';

void main() {
  final preferences = PreferencesManager();
  late FakeCityPlaces provider;
  final cairo = testCity('Cairo', code: 'EG', country: 'Egypt');
  final suggestion = CitySuggestion(
    id: 'cairo',
    label: 'Cairo, Cairo Governorate, Egypt',
    selection: cairo,
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.saveToken('picker-test');
    provider = FakeCityPlaces();
    provider.onAutocomplete = (_) async => [suggestion];
    provider.onResolve = (value) async => value.selection!;
    ScreenUtil.configure(
      data: const MediaQueryData(size: Size(390, 844)),
      designSize: const Size(390, 844),
      minTextAdapt: false,
      splitScreenMode: false,
    );
  });
  tearDown(() => preferences.clear());

  Future<void> show(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double scale = 1,
    TargetPlatform platform = TargetPlatform.android,
    ValueChanged<CitySelection?>? selected,
    Widget? home,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepositoryProvider<CityPlacesProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: darkTheme.copyWith(platform: platform),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home:
              home ??
              Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      final city = await pickCurrentCity(context);
                      selected?.call(city);
                    },
                    child: const Text('Open city'),
                  ),
                ),
              ),
        ),
      ),
    );
    if (home == null) {
      await tester.tap(find.text('Open city'));
      await tester.pumpAndSettle();
    }
  }

  Finder input() => find.descendant(
    of: find.byType(BottomSheet),
    matching: find.byType(TextField),
  );
  void expectDarkInput(WidgetTester tester) {
    final field = tester.widget<TextField>(input());
    expect(field.decoration!.filled, true);
    expect(field.decoration!.fillColor, DarkColors.darkgreyColor);
    expect(field.style!.color, DarkColors.whiteColor);
    expect(field.cursorColor, DarkColors.primaryColor);
    expect(field.decoration!.hintStyle!.color, DarkColors.greyColor);
    expect(field.decoration!.focusedBorder!.borderSide, BorderSide.none);
    expect(field.decoration!.enabledBorder!.borderSide, BorderSide.none);
    final selection = TextSelectionTheme.of(tester.element(input()));
    expect(selection.selectionHandleColor, DarkColors.primaryColor);
    expect(selection.cursorColor, DarkColors.primaryColor);
    expect(
      CupertinoTheme.of(tester.element(input())).selectionHandleColor,
      DarkColors.primaryColor,
    );
    final decoration = tester.widget<InputDecorator>(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(InputDecorator),
      ),
    );
    expect(decoration.decoration.fillColor, DarkColors.darkgreyColor);
    expect(decoration.decoration.fillColor, isNot(Colors.white));
  }

  testWidgets('iOS selection handles and cursor are orange', (tester) async {
    await show(tester, platform: TargetPlatform.iOS);
    expectDarkInput(tester);
    await tester.enterText(input(), 'Cairo');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).cursorColor,
      DarkColors.primaryColor,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'explicit charcoal input overrides global white fill before and during typing',
    (tester) async {
      await show(tester);
      expectDarkInput(tester);
      final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
      expect(sheet.backgroundColor, DarkColors.backgroundColor);
      expect(sheet.clipBehavior, Clip.antiAlias);
      expect(
        (sheet.shape! as RoundedRectangleBorder).borderRadius,
        const BorderRadius.vertical(top: Radius.circular(24)),
      );
      expect(
        tester.widget<Text>(find.text('Current City')).style!.color,
        DarkColors.whiteColor,
      );
      await tester.enterText(input(), 'C');
      await tester.pump();
      expectDarkInput(tester);
      expect(provider.calls, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'initial idle state has no empty outlined suggestions container',
    (tester) async {
      await show(tester);
      expect(
        find.descendant(
          of: find.byType(CityAutocompleteResults),
          matching: find.byType(Material),
        ),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'orange loading, debounce, muted country and selection still work',
    (tester) async {
      CitySelection? selected;
      final pending = Completer<List<CitySuggestion>>();
      provider.onAutocomplete = (_) => pending.future;
      await show(tester, selected: (city) => selected = city);
      await tester.enterText(input(), 'Cai');
      await tester.pump(const Duration(milliseconds: 349));
      expect(provider.calls, 0);
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(
        tester
            .widget<CupertinoActivityIndicator>(
              find.byType(CupertinoActivityIndicator),
            )
            .color,
        DarkColors.primaryColor,
      );
      await tester.pump(const Duration(milliseconds: 1));
      expect(provider.calls, 1);
      pending.complete([suggestion]);
      await tester.pumpAndSettle();
      expect(find.text('Cairo'), findsOneWidget);
      expect(find.text('Cairo Governorate, Egypt'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Cairo Governorate, Egypt')).style!.color,
        DarkColors.greyColor,
      );
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(CityAutocompleteResults),
              matching: find.byType(Material),
            )
            .first,
      );
      expect((material.shape! as RoundedRectangleBorder).side, BorderSide.none);
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();
      expect(selected, same(cairo));
      expect(find.byType(BottomSheet), findsNothing);
      expect(provider.detailsCalls, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('empty search is readable without an outlined box', (
    tester,
  ) async {
    provider.onAutocomplete = (_) async => [];
    await show(tester);
    await tester.enterText(input(), 'Nowhere');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('No cities found. Try another name.'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
    final panel = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(CityAutocompleteResults),
            matching: find.byType(Material),
          )
          .first,
    );
    expect((panel.shape! as RoundedRectangleBorder).side, BorderSide.none);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('error retry uses orange accents and retains search behavior', (
    tester,
  ) async {
    provider.onAutocomplete = (_) async =>
        throw const CityPlacesException('Offline');
    await show(tester);
    await tester.enterText(input(), 'Cai');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('Offline'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Retry cities'))
          .style!
          .foregroundColor!
          .resolve({}),
      DarkColors.primaryColor,
    );
    provider.onAutocomplete = (_) async => [suggestion];
    await tester.tap(find.text('Retry cities'));
    await tester.pumpAndSettle();
    expect(provider.calls, 2);
    expect(find.text('Cairo'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  for (final config in [
    (const Size(390, 844), 1.0, 320.0),
    (const Size(320, 568), 2.0, 280.0),
    (const Size(320, 568), 2.5, 300.0),
  ]) {
    testWidgets(
      'keyboard and large text scroll without overflow ${config.$1} scale ${config.$2}',
      (tester) async {
        await show(tester, size: config.$1, scale: config.$2);
        tester.view.viewInsets = FakeViewPadding(bottom: config.$3);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        await tester.enterText(input(), 'Cai');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expectDarkInput(tester);
        await tester.scrollUntilVisible(
          find.byType(ListTile),
          80,
          scrollable: find
              .descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.ensureVisible(find.byType(ListTile));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byType(ListTile));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final setup in [true, false]) {
    testWidgets(
      '${setup ? 'Profile Setup' : 'Edit Profile'} uses the same picker and unchanged location PUT',
      (tester) async {
        final api = backend.LocationApi();
        final repo = ProfileRepo(apiService: api);
        final user = CurrentUserCubit(profileRepo: repo);
        await user.load();
        final owner = ProfileCubit(profileRepo: repo, currentUser: user);
        await owner.loadProfile();
        final wizard = ProfileSetupCubit(
          repo: ProfileSetupRepo(apiService: api),
          currentUser: user,
        );
        final screen = setup
            ? BlocBuilder<ProfileSetupCubit, ProfileSetupState>(
                bloc: wizard,
                builder: (context, state) => Scaffold(
                  body: Step1BasicInfo(
                    fullNameController: wizard.fullNameController,
                    usernameController: wizard.usernameController,
                    usernameStatus: state.usernameStatus,
                    usernameMessage: state.usernameMessage,
                    onUsernameChanged: wizard.onUsernameChanged,
                    avatarFile: null,
                    onAvatarPicked: wizard.setAvatar,
                    currentLocation: state.currentLocation,
                    onCityChanged: wizard.setCity,
                    isSaving: state.isSaving,
                    onNext: wizard.saveBasicInfo,
                    onSkip: () {},
                  ),
                ),
              )
            : EditProfileScreen(
                profile: user.state.profile!,
                owner: owner,
                selectionRepo: editing.SelectionRepo(),
              );
        await show(tester, home: screen);
        await tester.pumpAndSettle();
        final field = setup
            ? find.text('Select your current city')
            : find.text('Select your current city');
        await tester.ensureVisible(field);
        await tester.tap(field);
        await tester.pumpAndSettle();
        expectDarkInput(tester);
        await tester.enterText(input(), 'Cai');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(ListTile));
        await tester.pumpAndSettle();
        if (!setup) {
          expect(api.calls.where((call) => call.startsWith('PUT')), isEmpty);
          await tester.tap(find.text('Save Changes'));
          await tester.pumpAndSettle();
        }
        expect(api.calls.where((call) => call.startsWith('PUT')), [
          'PUT profile/location',
        ]);
        expect(api.payloads.single, {'location': 'Cairo, EG'});
        expect(user.state.profile!.currentLocation, 'Cairo, EG');
        expect(api.calls, isNot(contains('PATCH settings')));
        await tester.pumpWidget(const SizedBox());
        await wizard.close();
        await owner.close();
        await user.close();
      },
    );
  }
}
