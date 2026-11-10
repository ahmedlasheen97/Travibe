import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_exceptions.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/profile/cubit/edit_profile_cubit.dart';
import 'package:travibe/features/profile/cubit/profile_cubit.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'package:travibe/features/profile/data/profile_repo.dart';
import 'package:travibe/features/profile/data/profile_update.dart';
import 'package:travibe/features/profile/screens/edit_profile_screen.dart';
import 'package:travibe/features/profile/screens/languages_screen.dart';
import 'package:travibe/features/profilesetup/data/profile_setup_repo.dart';
import 'package:travibe/features/profilesetup/data/reference_item.dart';
import 'fixtures.dart';

class PatchApi extends ApiService {
  Object? error;
  String? path;
  Map<String, dynamic>? body;
  @override
  Future<dynamic> patch(String endpoint, Map<String, dynamic> data) async {
    if (error != null) throw error!;
    path = endpoint;
    body = data;
    return {'data': []}; // PATCH response schema is intentionally not assumed.
  }
}

class EditingRepo extends MemoryProfileRepo {
  final writes = <Map<String, dynamic>>[];
  Object? saveError;
  Completer<void>? pending;
  @override
  Future<void> updateProfile(ProfileUpdate update) async {
    writes.add(update.toJson());
    if (pending != null) await pending!.future;
    if (saveError != null) throw saveError!;
    result = profile(
      name: update.toJson()['full_name'] as String? ?? 'Mona Hassan',
    );
  }
}

class SelectionRepo extends ProfileSetupRepo {
  @override
  Future<List<ReferenceItem>> loadCatalog(ReferenceKind kind) async => const [
    ReferenceItem(
      slug: 'arabic',
      name: 'العربية',
      nameEn: 'Arabic',
      nameAr: 'العربية',
    ),
    ReferenceItem(
      slug: 'new_slug',
      name: 'New language',
      nameEn: 'New language',
      nameAr: 'لغة',
    ),
  ];
}

void main() {
  setUp(() {
    ScreenUtil.configure(
      data: const MediaQueryData(size: Size(390, 844)),
      designSize: const Size(390, 844),
      minTextAdapt: false,
      splitScreenMode: false,
    );
  });
  test(
    'prefill preserves nullable values, response aliases and reference slugs',
    () {
      final model = ProfileModel.fromJson({
        ...profileJson(),
        'full_name': 'Real name',
        'nationality_code': 'EG',
        'gender': 'female',
      });
      final draft = ProfileDraft(model);
      expect(model.name, 'Real name');
      expect(model.nationalityCode, 'EG');
      expect(model.gender, 'female');
      expect(draft.isDirty, false);
      draft.set('languages_spoken', ['arabic']);
      expect(draft.isDirty, false);
      draft.set('bio', null);
      expect(draft.toUpdate().toJson(), {'bio': null});
      draft.set('bio', model.bio);
      expect(draft.isDirty, false);
      final sparse = ProfileDraft(const ProfileModel(id: '7'));
      sparse.set('username', null);
      expect(sparse.isDirty, false);
    },
  );

  test(
    'PATCH sends only changed fields, preserves null and avatar media ID',
    () async {
      final api = PatchApi();
      final repo = ProfileRepo(apiService: api);
      final draft = ProfileDraft(profile());
      draft.set('full_name', 'New name');
      draft.set('bio', null);
      draft.set('avatar_media_id', 42);
      await repo.updateProfile(draft.toUpdate());
      expect(api.path, 'profile');
      expect(api.body, {
        'full_name': 'New name',
        'bio': null,
        'avatar_media_id': 42,
      });
      expect(
        () => ProfileUpdate({'avatar_media_id': 0}),
        throwsA(isA<ApiError>()),
      );
    },
  );

  test(
    'validation enforces names, handles, bio, ISO, gender and selection bounds',
    () {
      for (final changes in [
        {'full_name': ''},
        {'full_name': 'a' * 256},
        {'username': 'ab'},
        {'username': 'a' * 31},
        {'username': 'bad handle'},
        {'bio': 'a' * 181},
        {'country_code': 'ZZ'},
        {'country_code': 'XK'},
        {'country_code': 'AC'},
        {'nationality_code': 'Egypt'},
        {'gender': 'unknown'},
        {'languages_spoken': <String>[]},
        {
          'languages_spoken': ['a', 'b', 'c', 'd', 'e'],
        },
        {'interests': List.generate(7, (i) => '$i')},
        {
          'travel_styles': ['a', 'b', 'c', 'd'],
        },
        {
          'interests': ['same', 'same'],
        },
        {
          'travel_styles': [''],
        },
        {'cover_photo': 1},
      ]) {
        expect(
          () => ProfileUpdate(changes),
          throwsA(isA<ApiError>()),
          reason: '$changes',
        );
      }
      expect(
        ProfileUpdate({
          'username': null,
          'bio': null,
          'country_code': 'EG',
          'nationality_code': null,
          'gender': null,
          'languages_spoken': null,
        }).toJson()['username'],
        isNull,
      );
      final draft = ProfileDraft(profile())..set('interests', null);
      expect(draft.clearsRequired, true);
      expect(draft.toUpdate().toJson(), {'interests': null});
    },
  );

  test(
    'unchanged selections retain slugs and selection reordering is not a change',
    () {
      final draft = ProfileDraft(
        const ProfileModel(
          id: '7',
          languageSelections: [
            ProfileReference(slug: 'x_y', name: 'Label'),
            ProfileReference(slug: 'a', name: 'Label'),
          ],
        ),
      );
      draft.set('languages_spoken', ['a', 'x_y']);
      expect(draft.isDirty, false);
      draft.set('languages_spoken', ['x_y']);
      expect(draft.toUpdate().toJson(), {
        'languages_spoken': ['x_y'],
      });
    },
  );

  test('PATCH maps network and timeout errors and preserves draft', () async {
    for (final type in [
      DioExceptionType.connectionError,
      DioExceptionType.receiveTimeout,
    ]) {
      final api = PatchApi()
        ..error = DioException(
          requestOptions: RequestOptions(path: 'profile'),
          type: type,
        );
      final draft = ProfileDraft(profile())..set('bio', 'Unsaved text');
      await expectLater(
        ProfileRepo(apiService: api).updateProfile(draft.toUpdate()),
        throwsA(isA<ApiError>()),
      );
      expect(draft.toUpdate().toJson(), {'bio': 'Unsaved text'});
    }
  });

  test(
    'duplicate saves are prevented and successful save refreshes owner',
    () async {
      final repo = EditingRepo()..pending = Completer<void>();
      final owner = ProfileCubit(profileRepo: repo);
      await owner.loadProfile();
      final editor = EditProfileCubit(owner);
      final draft = ProfileDraft(profile())..set('full_name', 'Updated');
      final first = editor.save(draft);
      expect(editor.state.saving, true);
      expect(await editor.save(draft), false);
      expect(repo.writes, hasLength(1));
      repo.pending!.complete();
      expect(await first, true);
      expect(editor.state.saved, true);
      expect(repo.reads, hasLength(2));
      expect((owner.state as ProfileLoaded).profile.name, 'Updated');
      expect(await editor.save(draft), false);
      await editor.close();
      await owner.close();
    },
  );

  for (final code in [401, 422]) {
    test('$code keeps draft intact and allows retry', () async {
      final failure = ApiError(
        message: 'Cannot save',
        statusCode: code,
        fieldErrors: code == 422
            ? {
                'username': ['Already taken'],
              }
            : {},
      );
      final repo = EditingRepo()..saveError = failure;
      final owner = ProfileCubit(profileRepo: repo);
      await owner.loadProfile();
      final editor = EditProfileCubit(owner);
      final draft = ProfileDraft(profile())..set('username', 'new_name');
      expect(await editor.save(draft), false);
      expect(editor.state.error, same(failure));
      expect(draft.toUpdate().toJson(), {'username': 'new_name'});
      expect(repo.reads, hasLength(1));
      repo.saveError = null;
      expect(await editor.save(draft), true);
      await editor.close();
      await owner.close();
    });
  }

  test('422 mapper retains all field-specific validation errors', () {
    final options = RequestOptions(path: 'profile');
    final failure = ApiExceptions.handleError(
      DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: options,
          statusCode: 422,
          data: {
            'message': 'Invalid',
            'errors': {
              'username': ['Already taken'],
              'interests.0': ['Invalid selection'],
            },
          },
        ),
      ),
    );
    expect(failure.statusCode, 422);
    expect(failure.message, 'Already taken');
    expect(failure.fieldErrors['username'], ['Already taken']);
    expect(failure.fieldErrors['interests.0'], ['Invalid selection']);
  });

  test(
    'public mode including is_me cannot PATCH and mismatched own identity is rejected',
    () async {
      final repo = EditingRepo();
      for (final publicId in [23, null]) {
        repo.result = profile(id: 23);
        final owner = ProfileCubit(profileRepo: repo, userId: publicId);
        await owner.loadProfile();
        final editor = EditProfileCubit(owner);
        expect(
          await editor.save(ProfileDraft(profile())..set('bio', 'Changed')),
          false,
        );
        expect(repo.writes, isEmpty);
        await editor.close();
        await owner.close();
      }
    },
  );

  test('pre-save reads cannot overwrite the post-save refresh', () async {
    final repo = EditingRepo();
    final owner = ProfileCubit(profileRepo: repo);
    await owner.loadProfile();
    repo.hold = true;
    final old = owner.refresh();
    final editor = EditProfileCubit(owner);
    final saved = editor.save(ProfileDraft(profile())..set('bio', 'Changed'));
    await Future<void>.delayed(Duration.zero);
    expect(repo.reads, hasLength(3));
    repo.reads.last.result.complete(profile(name: 'Committed'));
    expect(await saved, true);
    repo.reads[1].result.complete(profile(name: 'Stale'));
    await old;
    expect((owner.state as ProfileLoaded).profile.name, 'Committed');
    await editor.close();
    await owner.close();
  });

  test(
    'refresh failure after successful PATCH never retries the committed write',
    () async {
      final repo = EditingRepo();
      final owner = ProfileCubit(profileRepo: repo);
      await owner.loadProfile();
      repo.error = ApiError(message: 'Network error');
      final editor = EditProfileCubit(owner);
      expect(
        await editor.save(ProfileDraft(profile())..set('bio', 'Changed')),
        true,
      );
      expect(owner.state, isA<ProfileFailure>());
      repo.error = null;
      await owner.refresh();
      expect(repo.writes, hasLength(1));
      await editor.close();
      await owner.close();
    },
  );

  Future<ProfileCubit> showEditor(WidgetTester tester, EditingRepo repo) async {
    final owner = ProfileCubit(profileRepo: repo);
    await owner.loadProfile();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<bool>(
                  builder: (_) => EditProfileScreen(
                    profile: profile(),
                    owner: owner,
                    selectionRepo: SelectionRepo(),
                  ),
                ),
              ),
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    return owner;
  }

  testWidgets(
    'prefills actual values and failed save retains input and field errors',
    (tester) async {
      final repo = EditingRepo()
        ..saveError = ApiError(
          message: 'Already taken',
          statusCode: 422,
          fieldErrors: {
            'username': ['Already taken'],
          },
        );
      final owner = await showEditor(tester, repo);
      expect(find.text('Mona Hassan'), findsOneWidget);
      expect(find.text('Salma Ali'), findsNothing);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('username')))
            .controller!
            .text,
        'mona',
      );
      await tester.enterText(
        find.byKey(const ValueKey('username')),
        'new_name',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('username')))
            .controller!
            .text,
        'new_name',
      );
      expect(find.text('Already taken'), findsWidgets);
      expect(repo.writes.single, {'username': 'new_name'});
      await tester.runAsync(owner.close);
    },
  );

  testWidgets('successful edit returns to profile destination and refreshes', (
    tester,
  ) async {
    final repo = EditingRepo();
    final owner = await showEditor(tester, repo);
    await tester.enterText(find.byKey(const ValueKey('full_name')), 'New name');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(find.text('Open editor'), findsOneWidget);
    expect((owner.state as ProfileLoaded).profile.name, 'New name');
    expect(repo.writes.single, {'full_name': 'New name'});
    await tester.runAsync(owner.close);
  });

  testWidgets(
    'unsaved edits require discard and unchanged form sends no PATCH',
    (tester) async {
      final repo = EditingRepo();
      final owner = await showEditor(tester, repo);
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Save Changes'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byKey(const ValueKey('full_name')), 'Draft');
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Discard Changes?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Draft'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Open editor'), findsOneWidget);
      expect(repo.writes, isEmpty);
      await tester.runAsync(owner.close);
    },
  );

  testWidgets(
    'catalog selections use slugs and preserve existing localized labels',
    (tester) async {
      final repo = EditingRepo();
      final owner = await showEditor(tester, repo);
      await tester.scrollUntilVisible(
        find.text('Languages'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      final edit = find.descendant(
        of: find
            .ancestor(of: find.text('Languages'), matching: find.byType(Row))
            .first,
        matching: find.text('Edit'),
      );
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(find.byType(LanguagesScreen), findsOneWidget);
      expect(find.text('العربية'), findsOneWidget);
      await tester.tap(find.text('New language'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(repo.writes.single, {
        'languages_spoken': ['arabic', 'new_slug'],
      });
      await tester.runAsync(owner.close);
    },
  );
}
