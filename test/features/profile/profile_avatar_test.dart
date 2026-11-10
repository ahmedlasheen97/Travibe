import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:travibe/core/media/media_upload_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/profile/cubit/edit_profile_cubit.dart';
import 'package:travibe/features/profile/cubit/profile_cubit.dart';
import 'package:travibe/features/profile/data/profile_avatar_repo.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/profile/data/profile_update.dart';
import 'package:travibe/features/profile/screens/edit_profile_screen.dart';

import 'edit_profile_test.dart' show EditingRepo;
import 'fixtures.dart';

Uint8List _bytes() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAYAAAB/qH1jAAAAEklEQVR4nGP43+DwHxkzoAsAAHYhFfF34aTLAAAAAElFTkSuQmCC',
);
ProfileAvatarDraft _photo() =>
    ProfileAvatarDraft(name: 'avatar.png', bytes: _bytes());

class _Picker extends ImagePicker {
  XFile? result;
  Object? error;
  int calls = 0;
  ImageSource? source;
  bool? metadata;
  bool? photoPicker;
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    calls++;
    this.source = source;
    metadata = requestFullMetadata;
    final platform = ImagePickerPlatform.instance;
    if (platform is ImagePickerAndroid) {
      photoPicker = platform.useAndroidPhotoPicker;
    }
    expect(maxWidth, isNull);
    expect(maxHeight, isNull);
    expect(imageQuality, isNull);
    if (error != null) throw error!;
    return result;
  }
}

class _Photos extends ProfileAvatarRepo {
  ProfileAvatarDraft? result;
  Object? error;
  Completer<ProfileAvatarDraft?>? pending;
  int calls = 0;
  @override
  Future<ProfileAvatarDraft?> pick() async {
    calls++;
    if (error != null) throw error!;
    if (pending != null) return pending!.future;
    return result;
  }
}

class _Upload extends MediaUploadService {
  int calls = 0;
  Object? error;
  Completer<int>? pending;
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
    expect(filename, 'avatar.png');
    expect(contentType, 'image/png');
    expect(bytes, _bytes());
    onStage(MediaUploadStage.uploading);
    if (error != null) throw error!;
    if (pending != null) return pending!.future;
    onStage(MediaUploadStage.processing);
    return 77;
  }
}

void main() {
  Future<EditProfileCubit> editor(
    _Photos photos, {
    EditingRepo? repo,
    _Upload? upload,
  }) async {
    final owner = ProfileCubit(profileRepo: repo ?? EditingRepo());
    await owner.loadProfile();
    final result = EditProfileCubit(
      owner,
      avatarRepo: photos,
      mediaUpload: upload ?? _Upload(),
    );
    addTearDown(() async {
      await result.close();
      await owner.close();
    });
    return result;
  }

  test(
    'avatar MIME comes from actual bytes, never an extension or placeholder',
    () {
      ProfileAvatarDraft photo(List<int> bytes) => ProfileAvatarDraft(
        name: 'misleading.txt',
        bytes: Uint8List.fromList(bytes),
      );
      expect(_photo().contentType, 'image/png');
      expect(photo([255, 216, 255, 0]).contentType, 'image/jpeg');
      expect(photo([71, 73, 70, 56, 57, 97]).contentType, 'image/gif');
      expect(
        photo([82, 73, 70, 70, 0, 0, 0, 0, 87, 69, 66, 80]).contentType,
        'image/webp',
      );
      expect(photo([1, 2, 3]).contentType, isNull);
    },
  );

  test(
    'single native gallery uses scoped picker and validates immutable bytes',
    () async {
      final platform = ImagePickerPlatform.instance;
      final android = ImagePickerAndroid()..useAndroidPhotoPicker = false;
      ImagePickerPlatform.instance = android;
      addTearDown(() => ImagePickerPlatform.instance = platform);
      final picker = _Picker()
        ..result = XFile.fromData(
          _bytes(),
          path: '/local/avatar.png',
          name: 'avatar.png',
        );
      final selected = (await ProfileAvatarRepo(picker: picker).pick())!;
      expect(picker.calls, 1);
      expect(picker.source, ImageSource.gallery);
      expect(picker.metadata, false);
      expect(picker.photoPicker, true);
      expect(android.useAndroidPhotoPicker, false);
      expect(selected.name, 'avatar.png');
      expect(selected.bytes, _bytes());
      expect(() => selected.bytes[0] = 0, throwsUnsupportedError);
      picker.result = null;
      expect(await ProfileAvatarRepo(picker: picker).pick(), isNull);
    },
  );

  test(
    'invalid/empty images fail validation and native errors restore configuration',
    () async {
      final platform = ImagePickerPlatform.instance;
      final android = ImagePickerAndroid()..useAndroidPhotoPicker = false;
      ImagePickerPlatform.instance = android;
      addTearDown(() => ImagePickerPlatform.instance = platform);
      final picker = _Picker();
      for (final data in [
        Uint8List(0),
        Uint8List.fromList([1, 2, 3]),
      ]) {
        picker.result = XFile.fromData(data, name: 'bad.png');
        await expectLater(
          ProfileAvatarRepo(picker: picker).pick(),
          throwsA(isA<InvalidProfileAvatar>()),
        );
        expect(android.useAndroidPhotoPicker, false);
      }
      picker.error = PlatformException(code: 'photo_access_denied');
      await expectLater(
        ProfileAvatarRepo(picker: picker).pick(),
        throwsA(isA<PlatformException>()),
      );
      expect(android.useAndroidPhotoPicker, false);
    },
  );

  test(
    'preview selection/cancellation/failure preserves previous photo and profile',
    () async {
      final photos = _Photos()..result = _photo();
      final cubit = await editor(photos);
      final original = (cubit.owner.state as ProfileLoaded).profile;
      await cubit.pickAvatar();
      final selected = cubit.state.avatar;
      photos.result = null;
      await cubit.pickAvatar();
      expect(cubit.state.avatar, same(selected));
      photos.error = const InvalidProfileAvatar();
      await cubit.pickAvatar();
      expect(cubit.state.avatar, same(selected));
      expect(cubit.state.avatarError, contains('valid image'));
      expect((cubit.owner.state as ProfileLoaded).profile, same(original));
      cubit.discardAvatarPreview();
      expect(cubit.state.avatar, isNull);
      expect((cubit.owner.state as ProfileLoaded).profile, same(original));
    },
  );

  test(
    'busy selection prevents duplicate picks and saves; preview allows field PATCH',
    () async {
      final photos = _Photos()..pending = Completer();
      final repo = EditingRepo();
      final cubit = await editor(photos, repo: repo);
      final draft = ProfileDraft(profile())..set('bio', 'Keep draft');
      final selecting = cubit.pickAvatar();
      expect(cubit.state.selectingAvatar, true);
      await cubit.pickAvatar();
      cubit.discardAvatarPreview();
      expect(await cubit.save(draft), false);
      expect(photos.calls, 1);
      photos.pending!.complete(_photo());
      await selecting;
      final selected = cubit.state.avatar;
      expect(await cubit.save(draft), true);
      expect(repo.writes.single, {'bio': 'Keep draft', 'avatar_media_id': 77});
      expect(selected, isNotNull);
      expect(cubit.state.avatar, isNull);
      expect(cubit.state.saved, true);
      expect(draft.isDirty, false);
      expect(repo.reads, hasLength(2));
      expect(await cubit.save(draft), false);
      expect(repo.writes, hasLength(1));
    },
  );

  test(
    'unchanged form sends no PATCH; avatar-only save sends verified media ID',
    () async {
      final repo = EditingRepo();
      final upload = _Upload();
      final cubit = await editor(
        _Photos()..result = _photo(),
        repo: repo,
        upload: upload,
      );
      final draft = ProfileDraft(profile());
      expect(await cubit.save(draft), false);
      expect(upload.calls, 0);
      await cubit.pickAvatar();
      expect(await cubit.save(draft), true);
      expect(repo.writes.single, {'avatar_media_id': 77});
      expect(repo.reads, hasLength(2));
      expect(cubit.state.saved, true);
      expect(draft.isDirty, false);
    },
  );

  test(
    'unverified avatar IDs are excluded without changing ProfileUpdate support',
    () async {
      final repo = EditingRepo();
      final cubit = await editor(_Photos(), repo: repo);
      final draft = ProfileDraft(profile())..set('avatar_media_id', 123);
      expect(await cubit.save(draft), false);
      expect(repo.writes, isEmpty);
      draft.set('bio', null);
      expect(await cubit.save(draft), true);
      expect(repo.writes.single, {'bio': null});
      expect(ProfileUpdate({'avatar_media_id': 123}).toJson(), {
        'avatar_media_id': 123,
      });
    },
  );

  test(
    'failed 401/422 saves preserve preview, draft, errors and retry',
    () async {
      for (final code in [401, 422]) {
        final photos = _Photos()..result = _photo();
        final failure = ApiError(
          message: 'Cannot save',
          statusCode: code,
          fieldErrors: {
            'username': ['Already taken'],
          },
        );
        final repo = EditingRepo()..saveError = failure;
        final cubit = await editor(photos, repo: repo);
        await cubit.pickAvatar();
        final selected = cubit.state.avatar;
        final draft = ProfileDraft(profile())
          ..set('username', 'different_name');
        expect(await cubit.save(draft), false);
        expect(cubit.state.error, same(failure));
        expect(cubit.state.avatar, same(selected));
        expect(draft.changes, {'username': 'different_name'});
        repo.saveError = null;
        expect(await cubit.save(draft), true);
        expect(cubit.state.avatar, isNull);
        expect(draft.isDirty, false);
      }
    },
  );

  test(
    'preview saves prevent duplicates and do not restore stale session state',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = PreferencesManager();
      await prefs.init();
      await prefs.saveToken('test-save-owner-a');
      final repo = EditingRepo()..pending = Completer<void>();
      final cubit = await editor(_Photos()..result = _photo(), repo: repo);
      await cubit.pickAvatar();
      final draft = ProfileDraft(profile())..set('bio', 'Changed');
      final saving = cubit.save(draft);
      expect(cubit.state.saving, true);
      expect(cubit.state.avatar, isNotNull);
      expect(await cubit.save(draft), false);
      await Future<void>.delayed(Duration.zero);
      expect(repo.writes, hasLength(1));
      await prefs.saveToken('test-save-owner-b');
      repo.pending!.complete();
      expect(await saving, false);
      expect(cubit.state.sessionChanged, true);
      expect(cubit.state.avatar, isNull);
      expect(cubit.state.saved, false);
      expect(draft.isDirty, true);
      await prefs.clear();
    },
  );

  test(
    'confirmed field save refreshes canonical profile without changing its avatar',
    () async {
      const originalUrl = 'https://example.invalid/existing-avatar.png';
      final original = ProfileModel.fromJson({
        ...profileJson(),
        'avatar_url': originalUrl,
      });
      final repo = EditingRepo()..result = original;
      final cubit = await editor(_Photos()..result = _photo(), repo: repo);
      repo.hold = true;
      final draft = ProfileDraft(original)..set('full_name', 'Updated');
      final saving = cubit.save(draft);
      await Future<void>.delayed(Duration.zero);
      expect(repo.reads, hasLength(2));
      repo.reads.last.result.complete(
        ProfileModel.fromJson({
          ...profileJson(),
          'name': 'Updated',
          'avatar_url': originalUrl,
        }),
      );
      expect(await saving, true);
      expect(repo.writes.single, {'full_name': 'Updated'});
      expect(
        (cubit.owner.state as ProfileLoaded).profile.avatarUrl,
        originalUrl,
      );
      expect((cubit.owner.state as ProfileLoaded).profile.name, 'Updated');
      expect(cubit.state.avatar, isNull);
    },
  );

  test(
    'disposed editor does not acknowledge a late field save or restore preview state',
    () async {
      final repo = EditingRepo()..pending = Completer<void>();
      final owner = ProfileCubit(profileRepo: repo);
      await owner.loadProfile();
      final cubit = EditProfileCubit(
        owner,
        avatarRepo: _Photos()..result = _photo(),
        mediaUpload: _Upload(),
      );
      await cubit.pickAvatar();
      final draft = ProfileDraft(profile())..set('bio', 'Pending');
      final saving = cubit.save(draft);
      await Future<void>.delayed(Duration.zero);
      final pendingState = cubit.state;
      await cubit.close();
      repo.pending!.complete();
      expect(await saving, false);
      expect(cubit.state, same(pendingState));
      expect(draft.isDirty, true);
      await owner.close();
    },
  );

  test('acknowledging a PATCH preserves later edits and omitted fields', () {
    final draft = ProfileDraft(profile())..set('bio', null);
    final submitted = draft.toUpdate();
    draft.set('bio', 'Later edit');
    draft.set('full_name', 'Other unsent field');
    draft.markSaved(submitted);
    expect(draft.changes, {
      'bio': 'Later edit',
      'full_name': 'Other unsent field',
    });
    draft.set('bio', null);
    expect(draft.changes, {'full_name': 'Other unsent field'});
    final revert = ProfileDraft(profile())..set('bio', 'Submitted');
    final update = revert.toUpdate();
    revert.set('bio', profile().bio);
    revert.markSaved(update);
    expect(revert.changes, {'bio': profile().bio});
  });

  test(
    'upload failure preserves server profile and edits; retry and cached ready ID after PATCH failure',
    () async {
      final repo = EditingRepo();
      final upload = _Upload()..error = ApiError(message: 'Upload failed');
      final cubit = await editor(
        _Photos()..result = _photo(),
        repo: repo,
        upload: upload,
      );
      await cubit.pickAvatar();
      final photo = cubit.state.avatar;
      final original = (cubit.owner.state as ProfileLoaded).profile;
      final draft = ProfileDraft(profile())..set('bio', 'Unsaved');
      expect(await cubit.save(draft), false);
      expect(repo.writes, isEmpty);
      expect((cubit.owner.state as ProfileLoaded).profile, same(original));
      expect(cubit.state.avatar, same(photo));
      expect(draft.changes, {'bio': 'Unsaved'});
      upload.error = null;
      repo.saveError = ApiError(message: 'Invalid profile', statusCode: 422);
      expect(await cubit.save(draft), false);
      expect(cubit.state.avatar, same(photo));
      expect(upload.calls, 2);
      repo.saveError = null;
      expect(await cubit.save(draft), true);
      expect(
        upload.calls,
        2,
      ); // Reuse the ready media ID instead of uploading again.
      expect(repo.writes.last, {'bio': 'Unsaved', 'avatar_media_id': 77});
    },
  );

  test(
    'session change during upload prevents profile PATCH and ignores the late ID',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = PreferencesManager();
      await prefs.init();
      await prefs.saveToken('test-upload-a');
      final upload = _Upload()..pending = Completer<int>();
      final repo = EditingRepo();
      final cubit = await editor(
        _Photos()..result = _photo(),
        repo: repo,
        upload: upload,
      );
      await cubit.pickAvatar();
      final saving = cubit.save(ProfileDraft(profile()));
      await prefs.saveToken('test-upload-b');
      upload.pending!.complete(77);
      expect(await saving, false);
      expect(repo.writes, isEmpty);
      expect(cubit.state.sessionChanged, true);
      expect(cubit.state.avatar, isNull);
      await prefs.clear();
    },
  );

  test('gallery cannot open during existing profile save', () async {
    final photos = _Photos();
    final repo = EditingRepo()..pending = Completer<void>();
    final cubit = await editor(photos, repo: repo);
    final saving = cubit.save(ProfileDraft(profile())..set('bio', 'Changed'));
    await cubit.pickAvatar();
    expect(photos.calls, 0);
    repo.pending!.complete();
    expect(await saving, true);
  });

  test(
    'permission/plugin/platform errors are safe, recoverable and keep avatar',
    () async {
      final photos = _Photos()..result = _photo();
      final cubit = await editor(photos);
      await cubit.pickAvatar();
      final selected = cubit.state.avatar;
      for (final error in [
        PlatformException(
          code: 'photo_access_denied',
          message: 'sensitive native details',
        ),
        PlatformException(code: 'photo_access_restricted'),
        MissingPluginException('private path'),
        PlatformException(code: 'other'),
      ]) {
        photos.error = error;
        await cubit.pickAvatar();
        expect(cubit.state.avatar, same(selected));
        expect(cubit.state.selectingAvatar, false);
        expect(cubit.state.avatarError, isNotNull);
        expect(cubit.state.avatarError, isNot(contains('sensitive')));
        expect(cubit.state.avatarError, isNot(contains('private path')));
      }
      photos.error = null;
      await cubit.pickAvatar();
      expect(cubit.state.avatarError, isNull);
    },
  );

  test(
    'account changes clear preview and reject pending responses and later saves',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = PreferencesManager();
      await prefs.init();
      await prefs.saveToken('test-account-a');
      final photos = _Photos()..result = _photo();
      final repo = EditingRepo();
      final cubit = await editor(photos, repo: repo);
      await cubit.pickAvatar();
      photos.pending = Completer();
      final selecting = cubit.pickAvatar();
      await prefs.saveToken('test-account-b');
      expect(cubit.state.sessionChanged, true);
      expect(cubit.state.avatar, isNull);
      photos.pending!.complete(_photo());
      await selecting;
      await cubit.pickAvatar();
      expect(photos.calls, 2);
      expect(cubit.state.avatar, isNull);
      expect(
        await cubit.save(ProfileDraft(profile())..set('bio', 'Changed')),
        false,
      );
      expect(repo.writes, isEmpty);
      await prefs.clear();
    },
  );

  test('a changed owner identity cannot receive a stale local photo', () async {
    final photos = _Photos()..pending = Completer();
    final repo = EditingRepo();
    final cubit = await editor(photos, repo: repo);
    final selecting = cubit.pickAvatar();
    repo.result = profile(id: 8);
    await cubit.owner.refresh();
    photos.pending!.complete(_photo());
    await selecting;
    expect(cubit.state.avatar, isNull);
    expect(cubit.state.sessionChanged, true);
    expect((cubit.owner.state as ProfileLoaded).profile.id, '8');
  });

  test('logout clears existing preview', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesManager();
    await prefs.init();
    await prefs.saveToken('test-owner');
    final photos = _Photos()..result = _photo();
    final cubit = await editor(photos);
    await cubit.pickAvatar();
    await prefs.clear();
    expect(cubit.state.sessionChanged, true);
    expect(cubit.state.avatar, isNull);
  });

  test(
    'disposed editor rejects pending photo and public profile cannot select',
    () async {
      final photos = _Photos()..pending = Completer();
      final owner = ProfileCubit(profileRepo: EditingRepo());
      await owner.loadProfile();
      final cubit = EditProfileCubit(owner, avatarRepo: photos);
      final selecting = cubit.pickAvatar();
      await cubit.close();
      photos.pending!.complete(_photo());
      await selecting;
      expect(cubit.state.avatar, isNull);
      await owner.close();
      final publicOwner = ProfileCubit(profileRepo: EditingRepo(), userId: 7);
      await publicOwner.loadProfile();
      final publicEditor = EditProfileCubit(publicOwner, avatarRepo: photos);
      await publicEditor.pickAvatar();
      expect(photos.calls, 1);
      await publicEditor.close();
      await publicOwner.close();
    },
  );

  Future<ProfileCubit> show(
    WidgetTester tester,
    _Photos photos,
    EditingRepo repo, {
    _Upload? upload,
  }) async {
    final owner = ProfileCubit(profileRepo: repo);
    await owner.loadProfile();
    addTearDown(owner.close);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => EditProfileScreen(
                    profile: profile(),
                    owner: owner,
                    avatarRepo: photos,
                    mediaUpload: upload ?? _Upload(),
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

  Finder avatar() => find.byKey(const ValueKey('edit-profile-avatar'));
  Finder pick() => find.byKey(const ValueKey('pick-profile-avatar'));
  Finder save() => find.byType(ElevatedButton);

  testWidgets(
    'avatar plus text Save uploads, PATCHes and returns after refresh',
    (tester) async {
      final photos = _Photos()..result = _photo();
      final upload = _Upload()..pending = Completer<int>();
      final repo = EditingRepo();
      await show(tester, photos, repo, upload: upload);
      await tester.enterText(
        find.byKey(const ValueKey('full_name')),
        'Updated name',
      );
      await tester.tap(pick());
      await tester.pumpAndSettle();
      expect(
        find.text('Photo selected. Save Changes to upload.'),
        findsOneWidget,
      );
      expect(upload.calls, 0);
      expect(tester.widget<ElevatedButton>(save()).onPressed, isNotNull);
      await tester.tap(save());
      await tester.pump();
      expect(find.text('Uploading photo…'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(save()).onPressed, isNull);
      expect(repo.writes, isEmpty);
      // Exercise another physical tap while disabled, without asking the test
      // finder to hit-test a control that intentionally cannot receive taps.
      await tester.tapAt(tester.getCenter(save()));
      expect(upload.calls, 1);
      upload.pending!.complete(77);
      await tester.pumpAndSettle();
      expect(repo.writes.single, {
        'full_name': 'Updated name',
        'avatar_media_id': 77,
      });
      expect(repo.reads, hasLength(2));
      expect(find.text('Open editor'), findsOneWidget);
    },
  );

  testWidgets('avatar-only Save enabled, unchanged form disabled', (
    tester,
  ) async {
    final photos = _Photos()..result = _photo();
    final repo = EditingRepo();
    await show(tester, photos, repo);
    expect(tester.widget<ElevatedButton>(save()).onPressed, isNull);
    await tester.tap(pick());
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(save()).onPressed, isNotNull);
    await tester.tap(save());
    await tester.pumpAndSettle();
    expect(repo.writes.single, {'avatar_media_id': 77});
    expect(find.text('Open editor'), findsOneWidget);
  });

  testWidgets(
    'client and backend validation failures retain preview and field input',
    (tester) async {
      final photos = _Photos()..result = _photo();
      final repo = EditingRepo()
        ..saveError = ApiError(
          message: 'Already taken',
          statusCode: 422,
          fieldErrors: {
            'username': ['Already taken'],
          },
        );
      await show(tester, photos, repo);
      await tester.tap(pick());
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('username')), 'x');
      await tester.tap(save());
      await tester.pumpAndSettle();
      expect(repo.writes, isEmpty);
      expect(
        tester.widget<CircleAvatar>(avatar()).backgroundImage,
        isA<MemoryImage>(),
      );
      await tester.enterText(
        find.byKey(const ValueKey('username')),
        'taken_name',
      );
      await tester.pump(); // Rebuild the now-valid Save button.
      await tester.tap(save());
      await tester.pumpAndSettle();
      expect(repo.writes.single, {
        'username': 'taken_name',
        'avatar_media_id': 77,
      });
      expect(find.text('Already taken'), findsWidgets);
      expect(find.text('taken_name'), findsOneWidget);
      expect(
        tester.widget<CircleAvatar>(avatar()).backgroundImage,
        isA<MemoryImage>(),
      );
      repo.saveError = null;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(save());
      await tester.pumpAndSettle();
      expect(repo.writes, hasLength(2));
      expect(find.text('Open editor'), findsOneWidget);
    },
  );

  testWidgets(
    'pending picker shows progress, blocks duplicates and cancellation keeps current avatar',
    (tester) async {
      final photos = _Photos()..pending = Completer();
      await show(tester, photos, EditingRepo());
      await tester.tap(pick());
      await tester.pump();
      expect(find.text('Opening photo library…'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.tap(pick(), warnIfMissed: false);
      expect(photos.calls, 1);
      photos.pending!.complete(null);
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.widget<CircleAvatar>(avatar()).backgroundImage, isNull);
      expect(find.text('Mona Hassan'), findsOneWidget);
    },
  );

  testWidgets(
    'picker failure displays error and retains typed fields and preview without HTTP',
    (tester) async {
      final photos = _Photos()..result = _photo();
      final repo = EditingRepo();
      var requests = 0;
      await HttpOverrides.runZoned(
        () async {
          await show(tester, photos, repo);
          await tester.enterText(
            find.byKey(const ValueKey('username')),
            'keep_name',
          );
          await tester.tap(pick());
          await tester.pumpAndSettle();
          final image = tester.widget<CircleAvatar>(avatar()).backgroundImage;
          photos.error = PlatformException(code: 'photo_access_denied');
          await tester.tap(pick());
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('avatar-error')), findsOneWidget);
          expect(tester.widget<CircleAvatar>(avatar()).backgroundImage, image);
          expect(find.text('keep_name'), findsOneWidget);
        },
        createHttpClient: (_) {
          requests++;
          throw StateError('No avatar network allowed');
        },
      );
      expect(requests, 0);
      expect(repo.writes, isEmpty);
    },
  );

  testWidgets(
    'session changes hide old fields and preview while late picker is ignored',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await PreferencesManager().init();
      await PreferencesManager().saveToken('test-widget-a');
      final photos = _Photos()..pending = Completer();
      await show(tester, photos, EditingRepo());
      await tester.tap(pick());
      await tester.pump();
      await tester.runAsync(
        () => PreferencesManager().saveToken('test-widget-b'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Your session changed. Reopen Edit Profile.'),
        findsOneWidget,
      );
      expect(find.text('Mona Hassan'), findsNothing);
      photos.pending!.complete(_photo());
      await tester.pumpAndSettle();
      expect(avatar(), findsNothing);
      await tester.runAsync(() => PreferencesManager().clear());
    },
  );
}
