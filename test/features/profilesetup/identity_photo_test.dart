import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:dotted_border/dotted_border.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/widgets/custom_text_field.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/media/media_upload_service.dart';
import 'package:travibe/core/reference/countries_repo.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/custom_button.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/data/profile_avatar_repo.dart';
import 'package:travibe/features/profile/data/profile_repo.dart';
import 'package:travibe/features/profilesetup/cubit/profile_setup_cubit.dart';
import 'package:travibe/features/profilesetup/data/profile_identity_validation.dart';
import 'package:travibe/features/profilesetup/data/profile_setup_repo.dart';
import 'package:travibe/features/profilesetup/screens/profile_setup_screen.dart';
import 'package:travibe/features/profilesetup/widgets/step1_basic_info.dart';
import 'package:travibe/features/profilesetup/widgets/profile_country_picker.dart';
import '../../core/media/media_upload_test.dart' show MediaApi, StorageAdapter;

class SetupApi extends MediaApi {
  final profile = <String, dynamic>{
    'id': 7,
    'name': 'Saved Name',
    'username': 'saved_user',
    'country_code': 'EG',
    'current_location': 'Cairo, EG',
    'avatar_url': null,
  };
  final patches = <Map<String, dynamic>>[];
  Object? patchError;
  Object? profileError;
  Completer<dynamic>? patchGate;
  Completer<dynamic>? profileGate;
  Completer<dynamic>? checkGate;
  bool available = true;
  bool sparseAvatar = false;
  bool sparseIdentity = false;
  Map<String, dynamic> result() => {
    'data': Map.of(profile),
    'meta': {
      'profile_completed': false,
      'profile_setup_step': 'languages_interests',
    },
  };
  @override
  Future<dynamic> patch(String endpoint, Map<String, dynamic> data) async {
    expect(endpoint, 'profile/setup');
    calls.add('PATCH $endpoint');
    patches.add(Map.of(data));
    if (patchError != null) throw patchError!;
    if (patchGate != null) return patchGate!.future;
    profile.addAll(data);
    if (data.containsKey('full_name')) profile['name'] = data['full_name'];
    if (data.containsKey('avatar_media_id')) {
      profile['avatar_url'] = 'https://example.invalid/avatar.png';
    }
    final response = result();
    if (sparseAvatar) (response['data'] as Map).remove('avatar_url');
    if (sparseIdentity) (response['data'] as Map).remove('email_verified_at');
    return response;
  }

  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
    if (endpoint == 'profile') {
      calls.add('GET profile');
      if (profileError != null) throw profileError!;
      if (profileGate != null) return profileGate!.future;
      return {'data': Map.of(profile)};
    }
    if (endpoint == 'profile/username-availability') {
      calls.add('GET $endpoint');
      if (checkGate != null) return checkGate!.future;
      return {
        'data': {
          'username': queryParameters!['username'],
          'available': available,
        },
      };
    }
    if (endpoint == 'reference/travel-styles') return {'data': <dynamic>[]};
    return super.get(endpoint, queryParameters: queryParameters);
  }
}

class Countries extends ProfileSetupRepo {
  Countries({required super.apiService});
  @override
  Future<List<ReferenceCountry>> loadCountries(String locale) async => const [
    ReferenceCountry(code: 'EG', name: 'Egypt', nameEn: 'Egypt', nameAr: 'مصر'),
  ];
}

class Photos extends ProfileAvatarRepo {
  int calls = 0;
  Object? error;
  Completer<ProfileAvatarDraft?>? gate;
  final photo = ProfileAvatarDraft(
    name: 'photo.png',
    bytes: base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAYAAAB/qH1jAAAAEklEQVR4nGP43+DwHxkzoAsAAHYhFfF34aTLAAAAAElFTkSuQmCC',
    ),
  );
  @override
  Future<ProfileAvatarDraft?> pick() async {
    calls++;
    if (error != null) throw error!;
    return gate == null ? photo : gate!.future;
  }
}

class Upload extends MediaUploadService {
  int calls = 0;
  Object? error;
  Completer<int>? gate;
  CancelToken? cancel;
  String? contentTypeSeen;
  @override
  Future<int> upload({
    required String filename,
    required String contentType,
    required Uint8List bytes,
    required bool Function() isActive,
    required CancelToken cancelToken,
    required void Function(MediaUploadStage) onStage,
    void Function(int, int)? onProgress,
  }) async {
    calls++;
    cancel = cancelToken;
    contentTypeSeen = contentType;
    onStage(MediaUploadStage.uploading);
    if (error != null) throw error!;
    return gate == null ? 19 : gate!.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
          'Plus Jakarta Sans',
        )..addFont(rootBundle.load('assets/fonts/PlusJakartaSans-Regular.ttf')))
        .load();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('setup-test-session');
  });
  tearDown(() => PreferencesManager().clear());
  ProfileSetupCubit make(
    SetupApi api, {
    Photos? photos,
    MediaUploadService? upload,
    CurrentUserCubit? current,
  }) {
    final service = upload ?? Upload();
    final cubit = ProfileSetupCubit(
      repo: Countries(apiService: api),
      profileRepo: ProfileRepo(apiService: api),
      avatarRepo: photos ?? Photos(),
      mediaUpload: service,
      currentUser: current,
    );
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
      service.close();
    });
    return cubit;
  }

  test('identity follows required and documented username shape rules', () {
    expect(ProfileIdentityValidation.fullName('   '), isNotNull);
    expect(ProfileIdentityValidation.fullName('  Alice  '), isNull);
    expect(ProfileIdentityValidation.fullName('a' * 256), isNotNull);
    for (final name in [
      '',
      '  ',
      'ab',
      '.alice',
      'alice.',
      'a-b',
      'a b',
      'a' * 31,
    ]) {
      expect(ProfileIdentityValidation.username(name), isNotNull, reason: name);
    }
    for (final name in ['alice', 'a.b', '_alice_', 'alice_2']) {
      expect(ProfileIdentityValidation.username(name), isNull);
    }
  });
  test(
    'empty required identity never reaches PATCH and exposes inline errors',
    () async {
      final api = SetupApi();
      final cubit = make(api);
      cubit.fullNameController.text = '  ';
      await cubit.saveBasicInfo();
      expect(api.patches, isEmpty);
      expect(
        cubit.state.fieldErrors.keys,
        containsAll(['full_name', 'username']),
      );
    },
  );
  test('country maps only to country_code and identity is trimmed', () async {
    final api = SetupApi();
    final cubit = make(api);
    cubit.fullNameController.text = '  Alice  ';
    cubit.usernameController.text = ' alice ';
    cubit.setCountry('EG');
    await cubit.saveBasicInfo();
    expect(api.patches.single, {
      'full_name': 'Alice',
      'username': 'alice',
      'country_code': 'EG',
    });
    expect(api.profile['current_location'], 'Cairo, EG');
    expect(cubit.state.step, 1);
    expect(cubit.goBack(), true);
    expect(cubit.fullNameController.text, '  Alice  ');
  });
  test('duplicate username preserves draft and server field error', () async {
    final api = SetupApi()
      ..patchError = ApiError(
        message: 'Username already taken',
        statusCode: 422,
        fieldErrors: {
          'username': ['Username already taken'],
        },
      );
    final cubit = make(api);
    cubit.fullNameController.text = 'Alice';
    cubit.usernameController.text = 'alice';
    await cubit.saveBasicInfo();
    expect(cubit.state.step, 0);
    expect(cubit.state.usernameStatus, UsernameStatus.invalid);
    expect(cubit.state.fieldErrors['username'], ['Username already taken']);
    expect(cubit.usernameController.text, 'alice');
  });
  testWidgets(
    'availability debounce ignores stale responses and session changes',
    (tester) async {
      final api = SetupApi()..checkGate = Completer<dynamic>();
      final cubit = make(api);
      cubit.onUsernameChanged('alice');
      await tester.pump(const Duration(milliseconds: 501));
      final first = api.checkGate!;
      api.checkGate = null;
      cubit.onUsernameChanged('alicia');
      await tester.pump(const Duration(milliseconds: 501));
      await tester.pump();
      first.complete({
        'data': {'username': 'alice', 'available': false},
      });
      await tester.pump();
      expect(cubit.state.normalizedUsername, 'alicia');
      await PreferencesManager().clearSession();
      expect(cubit.usernameController.text, '');
      expect(cubit.state.usernameStatus, UsernameStatus.idle);
    },
  );
  test(
    'picker uploads, attaches ID, updates current user and restores after restart',
    () async {
      final api = SetupApi();
      final photos = Photos();
      final upload = Upload();
      final current = CurrentUserCubit(
        profileRepo: ProfileRepo(apiService: api),
      );
      addTearDown(current.close);
      await current.load();
      final cubit = make(api, photos: photos, upload: upload, current: current);
      await cubit.pickAvatar();
      expect(photos.calls, 1);
      expect(upload.calls, 1);
      expect(api.patches.single, {'avatar_media_id': 19});
      expect(cubit.state.avatar, isNull);
      expect(cubit.state.avatarUrl, 'https://example.invalid/avatar.png');
      expect(current.state.profile!.avatarUrl, cubit.state.avatarUrl);
      expect(cubit.state.step, 0); // A photo save does not advance the wizard.
      final reopened = make(api);
      await reopened.restore();
      expect(reopened.state.avatarUrl, cubit.state.avatarUrl);
      expect(reopened.fullNameController.text, 'Saved Name');
      expect(reopened.usernameController.text, 'saved_user');
    },
  );
  test(
    'sparse setup responses do not erase verified current-user metadata',
    () async {
      final api = SetupApi()..sparseIdentity = true;
      api.profile.addAll({
        'email': 'test@example.invalid',
        'email_verified_at': '2026-11-01T00:00:00Z',
        'profile_completed': false,
      });
      final current = CurrentUserCubit(
        profileRepo: ProfileRepo(apiService: api),
      );
      addTearDown(current.close);
      await current.load();
      final cubit = make(api, current: current);
      await cubit.pickAvatar();
      expect(current.state.profile!.emailVerifiedAt, '2026-11-01T00:00:00Z');
      expect(
        current.state.profile!.avatarUrl,
        'https://example.invalid/avatar.png',
      );
      expect(api.calls.last, 'GET profile');
    },
  );
  test(
    'real shared presign, storage PUT, finalize and polling precede setup attachment',
    () async {
      final api = SetupApi();
      final storage = StorageAdapter()
        ..onRequest = () => api.calls.add('PUT storage');
      final service = MediaUploadService(
        api: api,
        storageAdapter: storage,
        wait: (_) async {},
        now: () => DateTime.utc(2026),
      );
      final cubit = make(api, upload: service);
      await cubit.pickAvatar();
      expect(api.calls, [
        'POST media/presign',
        'PUT storage',
        'POST media/19/finalize',
        'GET media/19',
        'GET media/19',
        'GET media/19',
        'PATCH profile/setup',
      ]);
      expect(api.patches.single, {'avatar_media_id': 19});
      expect(storage.request!.headers.containsKey('Authorization'), false);
    },
  );
  test('upload failure retains preview and explicit retry succeeds', () async {
    final api = SetupApi();
    final upload = Upload()..error = ApiError(message: 'Offline. Retry photo.');
    final cubit = make(api, upload: upload);
    await cubit.pickAvatar();
    expect(cubit.state.avatar, isNotNull);
    expect(cubit.state.avatarError, contains('Offline'));
    expect(api.patches, isEmpty);
    upload.error = null;
    await cubit.uploadAvatar();
    expect(upload.calls, 2);
    expect(api.patches, hasLength(1));
    expect(cubit.state.avatarError, isNull);
  });
  test(
    'attachment failure retries without uploading the same ready media again',
    () async {
      final api = SetupApi()
        ..patchError = ApiError(message: 'Save unavailable');
      final upload = Upload();
      final cubit = make(api, upload: upload);
      await cubit.pickAvatar();
      expect(cubit.state.avatar, isNotNull);
      api.patchError = null;
      await cubit.uploadAvatar();
      expect(upload.calls, 1);
      expect(api.patches, hasLength(2));
    },
  );
  test(
    'confirmed attachment with failed canonical GET retries only GET',
    () async {
      final api = SetupApi()
        ..sparseAvatar = true
        ..profileError = ApiError(message: 'Offline');
      final upload = Upload();
      final cubit = make(api, upload: upload);
      await cubit.pickAvatar();
      expect(cubit.state.avatar, isNotNull);
      api.profileError = null;
      await cubit.uploadAvatar();
      expect(upload.calls, 1);
      expect(api.patches, hasLength(1));
      expect(cubit.state.avatarUrl, isNotNull);
    },
  );
  for (final close in [false, true]) {
    test(
      'late upload cannot attach after ${close ? 'disposal' : 'account change'}',
      () async {
        final api = SetupApi();
        final upload = Upload()..gate = Completer<int>();
        final cubit = make(api, upload: upload);
        final picking = cubit.pickAvatar();
        await Future<void>.delayed(Duration.zero);
        if (close) {
          await cubit.close();
        } else {
          await PreferencesManager().saveToken('different-session');
        }
        expect(upload.cancel!.isCancelled, true);
        upload.gate!.complete(19);
        await picking;
        expect(api.patches, isEmpty);
        if (!close) expect(cubit.state.avatar, isNull);
        if (close) expect(cubit.isClosed, true);
      },
    );
  }
  test(
    'duplicate picker/upload calls and discard cannot create extra attachments',
    () async {
      final api = SetupApi();
      final photos = Photos();
      final upload = Upload()..gate = Completer<int>();
      final cubit = make(api, photos: photos, upload: upload);
      final pending = cubit.pickAvatar();
      await Future<void>.delayed(Duration.zero);
      await cubit.pickAvatar();
      await cubit.uploadAvatar();
      expect(photos.calls, 1);
      expect(upload.calls, 1);
      cubit.discardAvatar();
      upload.gate!.complete(19);
      await pending;
      expect(api.patches, isEmpty);
      expect(cubit.state.avatar, isNull);
    },
  );
  test('permission denial does not upload or lose existing photo', () async {
    final api = SetupApi();
    final photos = Photos()
      ..error = PlatformException(code: 'photo_access_denied');
    final cubit = make(api, photos: photos);
    await cubit.restore();
    await cubit.pickAvatar();
    expect(cubit.state.avatarError, contains('settings'));
    expect(api.patches, isEmpty);
  });
  test(
    'restore cannot replace identity edited while GET was pending',
    () async {
      final api = SetupApi()..profileGate = Completer<dynamic>();
      final cubit = make(api);
      final restore = cubit.restore();
      cubit.fullNameController.text = 'New draft';
      api.profileGate!.complete({'data': api.profile});
      await restore;
      expect(cubit.fullNameController.text, 'New draft');
    },
  );
  test('restore errors expose a real retry and retain the draft', () async {
    final api = SetupApi()..profileError = ApiError(message: 'Offline');
    final cubit = make(api);
    await cubit.restore();
    expect(cubit.state.restoreError, isNotNull);
    api.profileError = null;
    await cubit.restore();
    expect(cubit.state.restoreError, isNull);
    expect(cubit.fullNameController.text, 'Saved Name');
  });

  test(
    'duplicate basic saves coalesce and late account responses cannot advance',
    () async {
      final api = SetupApi()..patchGate = Completer<dynamic>();
      final cubit = make(api);
      cubit.fullNameController.text = 'Alice';
      cubit.usernameController.text = 'alice';
      final save = cubit.saveBasicInfo();
      await Future<void>.delayed(Duration.zero);
      await cubit.saveBasicInfo();
      expect(api.patches, hasLength(1));
      await PreferencesManager().saveToken('next-account');
      api.patchGate!.complete(api.result());
      await save;
      expect(cubit.state.step, 0);
      expect(cubit.fullNameController.text, '');
    },
  );
  test(
    'late avatar attachment cannot publish into a switched account',
    () async {
      final api = SetupApi()..patchGate = Completer<dynamic>();
      final cubit = make(api);
      final pending = cubit.pickAvatar();
      await Future<void>.delayed(Duration.zero);
      expect(api.patches, hasLength(1));
      await PreferencesManager().saveToken('next-account');
      api.profile['avatar_url'] = 'https://example.invalid/old-account.png';
      api.patchGate!.complete(api.result());
      await pending;
      expect(cubit.state.avatarUrl, isNull);
      expect(cubit.state.avatar, isNull);
    },
  );

  Future<void> show(
    WidgetTester tester,
    ProfileSetupCubit cubit, {
    Size size = const Size(390, 844),
    double scale = 1,
    String language = 'en',
    bool whole = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          locale: Locale(language),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: whole
              ? ProfileSetupScreen(createCubit: (_) => cubit)
              : Scaffold(
                  body: BlocBuilder<ProfileSetupCubit, ProfileSetupState>(
                    bloc: cubit,
                    builder: (_, _) => Step1BasicInfo(cubit: cubit),
                  ),
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder placeholder() => find.byIcon(Icons.person_rounded);
  testWidgets(
    'identity keeps shared fields, 16px labels, 24px gap and restored silhouette',
    (tester) async {
      final cubit = make(SetupApi());
      await show(tester, cubit);
      expect(
        tester.getTopLeft(find.text('Full Name *')).dy -
            tester.getBottomLeft(find.text('Help others recognize you')).dy,
        closeTo(24, .01),
      );
      for (final label in ['Full Name *', 'User Name *', 'Current Country']) {
        final text = tester.widget<Text>(find.text(label));
        expect(text.style!.fontSize, 16);
        expect(text.style!.fontFamily, 'Plus Jakarta Sans');
        expect(text.style!.fontWeight, FontWeight.w600);
        expect(text.style!.color, Colors.white);
        if (text.textSpan != null) {
          expect(
            ((text.textSpan as TextSpan).children!.last as TextSpan)
                .style!
                .color,
            const Color(0xFFE45C10),
          );
        }
      }
      final fields = tester
          .widgetList<CustomTextField>(find.byType(CustomTextField))
          .toList();
      expect(fields, hasLength(2));
      expect(fields.first.prefixIcon, isNull);
      expect(fields.first.reservePrefixSpace, false);
      expect(
        (fields.last.prefixIcon as Icon).icon,
        Icons.alternate_email_rounded,
      );
      final input = find.byType(TextField).first;
      final hint = find.text('enter your full name');
      expect(
        tester.getTopLeft(hint).dx - tester.getTopLeft(input).dx,
        closeTo(20, .01),
      );
      final at = find.byIcon(Icons.alternate_email_rounded);
      expect(
        tester.getTopLeft(find.text('enter your username')).dx -
            tester.getTopRight(at).dx,
        closeTo(8, .01),
      );
      expect(placeholder(), findsOneWidget);
      final icon = tester.widget<Icon>(placeholder());
      expect(icon.size, 48);
      expect(icon.color, Colors.grey);
      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.radius, 56);
      expect(avatar.backgroundColor, const Color(0xFFE0E0E0));
      expect(
        tester.getCenter(placeholder()),
        tester.getCenter(find.byType(CircleAvatar)),
      );
      expect(
        find.descendant(
          of: find.byType(CircleAvatar),
          matching: find.byType(SvgPicture),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final size in const [
    Size(320, 568),
    Size(375, 812),
    Size(390, 844),
    Size(430, 932),
  ]) {
    testWidgets(
      'avatar retains circular geometry and about 12–16 even dashes at $size',
      (tester) async {
        final cubit = make(SetupApi());
        await show(tester, cubit, size: size);
        final border = tester.widget<DottedBorder>(find.byType(DottedBorder));
        expect(border.options, isA<CircularDottedBorderOptions>());
        expect(border.options.color, const Color(0xFFE45C10));
        expect(border.options.strokeWidth, 1.5);
        expect(border.options.padding, const EdgeInsets.all(6));
        final bounds = tester.getRect(find.byType(DottedBorder));
        expect(bounds.width, closeTo(124, .001));
        expect(bounds.height, closeTo(124, .001));
        final period = border.options.dashPattern.reduce((a, b) => a + b);
        // DottedBorder's existing painter fits a whole number of equal periods
        // to the circular path, avoiding a separate seam gap.
        expect(
          (math.pi * bounds.width / period).ceil(),
          inInclusiveRange(12, 16),
        );
        expect(border.options.dashPattern.first, greaterThan(6));
        expect(border.options.dashPattern.last, greaterThan(4));
        final badge = find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.constraints?.maxWidth == 32 &&
              w.constraints?.maxHeight == 32,
        );
        expect(
          (tester.getBottomRight(badge) -
                  (bounds.bottomRight - const Offset(4, 4)))
              .distance,
          lessThan(.001),
        );
        expect(
          tester.getCenter(placeholder()),
          tester.getCenter(find.byType(CircleAvatar)),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final size in const [Size(375, 812), Size(390, 844)]) {
    testWidgets(
      'first setup form and Next fit standard portrait $size at rest',
      (tester) async {
        tester.view.padding = FakeViewPadding(
          top: size.width == 375 ? 44 : 59,
          bottom: 34,
        );
        tester.view.viewPadding = FakeViewPadding(
          top: size.width == 375 ? 44 : 59,
          bottom: 34,
        );
        final cubit = make(SetupApi());
        await show(tester, cubit, size: size, whole: true);
        try {
          final scroll = find
              .descendant(
                of: find.byType(Step1BasicInfo),
                matching: find.byType(Scrollable),
              )
              .first;
          final viewport = tester.getRect(find.byType(Step1BasicInfo));
          final next = tester.getRect(
            find.descendant(
              of: find.byType(Step1BasicInfo),
              matching: find.byType(CustomButton),
            ),
          );
          expect(next.bottom, lessThanOrEqualTo(viewport.bottom));
          expect(next.top, greaterThanOrEqualTo(viewport.top));
          expect(tester.state<ScrollableState>(scroll).position.pixels, 0);
          expect(find.text('Next').first.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
        }
      },
    );
  }
  testWidgets(
    'required labels, Next locking, inline errors and country selection',
    (tester) async {
      final api = SetupApi();
      final cubit = make(api);
      await show(tester, cubit);
      expect(find.text('Full Name *'), findsOneWidget);
      expect(find.text('User Name *'), findsOneWidget);
      expect(find.text('Skip For Now'), findsNothing);
      final button = find.byType(CustomButton);
      expect(tester.widget<CustomButton>(button).onPressed, isNull);
      await tester.enterText(find.byType(TextFormField).first, '  ');
      await tester.pump();
      expect(find.text('Full name is required.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, 'Alice');
      await tester.enterText(find.byType(TextFormField).last, 'alice');
      await tester.pump(const Duration(milliseconds: 501));
      await tester.pump();
      expect(tester.widget<CustomButton>(button).onPressed, isNotNull);
      await tester.ensureVisible(find.text('Select your current country'));
      await tester.tap(find.text('Select your current country'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Egypt'));
      await tester.pumpAndSettle();
      expect(cubit.state.countryCode, 'EG');
      expect(api.patches, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('whole wizard removes Skip in both identity and language steps', (
    tester,
  ) async {
    final cubit = make(SetupApi());
    await show(tester, cubit, whole: true);
    expect(find.text('Skip For Now'), findsNothing);
    cubit.onPageChanged(1);
    cubit.pageController.jumpToPage(1);
    await tester.pumpAndSettle();
    expect(find.text('Skip For Now'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'photo preview and one compact indicator stay visible while pending',
    (tester) async {
      final upload = Upload()..gate = Completer<int>();
      final cubit = make(SetupApi(), upload: upload);
      await show(tester, cubit);
      expect(placeholder(), findsOneWidget);
      final pending = cubit.pickAvatar();
      await tester.pump();
      await tester.pump();
      expect(
        tester.widget<CircleAvatar>(find.byType(CircleAvatar)).backgroundImage,
        isA<MemoryImage>(),
      );
      expect(placeholder(), findsNothing);
      expect(
        cubit.state.uploadingAvatar,
        true,
        reason: cubit.state.avatarError,
      );
      cubit.discardAvatar();
      upload.gate!.complete(19);
      await pending;
      await tester.pump();
      await tester.pump();
      expect(placeholder(), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Next and Back preserve saved identity and never expose Skip', (
    tester,
  ) async {
    final api = SetupApi();
    final cubit = make(api);
    await show(tester, cubit, whole: true);
    await tester.enterText(find.byType(TextFormField).first, 'New Name');
    await tester.scrollUntilVisible(
      find.byType(CustomButton).first,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Next').first);
    await tester.pumpAndSettle();
    expect(cubit.state.step, 1);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(cubit.state.step, 0);
    expect(cubit.fullNameController.text, 'New Name');
    expect(cubit.usernameController.text, 'saved_user');
    expect(find.text('Skip For Now'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'step 1 has no back button and system back keeps setup and pending photo',
    (tester) async {
      final api = SetupApi();
      final upload = Upload()..gate = Completer<int>();
      final cubit = make(api, upload: upload);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            theme: darkTheme,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ProfileSetupScreen(createCubit: (_) => cubit),
                    ),
                  ),
                  child: const Text('Open setup'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open setup'));
      await tester.pumpAndSettle();
      final pending = cubit.pickAvatar();
      await tester.pump();
      await tester.pump();
      expect(find.byTooltip('Back'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ProfileSetupScreen), findsOneWidget);
      expect(find.text('Open setup'), findsNothing);
      expect(cubit.state.avatar, isNotNull);
      expect(upload.cancel!.isCancelled, false);
      upload.gate!.complete(19);
      await pending;
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('back between setup steps returns to the previous step', (
    tester,
  ) async {
    final cubit = make(SetupApi());
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: ProfileSetupScreen(createCubit: (_) => cubit),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back'), findsNothing);
    cubit.pageController.jumpToPage(2);
    await tester.pumpAndSettle();
    expect(cubit.state.step, 2);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(cubit.state.step, 1);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(cubit.state.step, 0);
    expect(find.byTooltip('Back'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(cubit.state.step, 0);
    expect(find.byType(ProfileSetupScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'country sheet error retries real catalog load and handles landscape keyboard',
    (tester) async {
      var calls = 0;
      final picker = ProfileCountryPicker(
        locale: 'ar',
        load: (_) async {
          calls++;
          if (calls == 1) throw ApiError(message: 'Offline');
          return const [
            ReferenceCountry(
              code: 'EG',
              name: 'مصر',
              nameEn: 'Egypt',
              nameAr: 'مصر',
            ),
          ];
        },
      );
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            theme: darkTheme,
            home: Scaffold(body: picker),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.tap(find.text('Unable to load countries. Retry'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('مصر'), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 270);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final size in const [
    Size(320, 568),
    Size(375, 812),
    Size(393, 852),
    Size(430, 932),
    Size(844, 390),
  ]) {
    for (final language in ['en', 'ar']) {
      testWidgets(
        'identity form scrolls $size $language with 2x text and keyboard',
        (tester) async {
          final cubit = make(SetupApi());
          await show(tester, cubit, size: size, scale: 2, language: language);
          tester.view.viewInsets = const FakeViewPadding(bottom: 270);
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byType(CustomButton),
            180,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(find.text('Next').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
