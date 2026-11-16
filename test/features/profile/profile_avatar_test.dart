import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:travibe/core/media/media_upload_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/screen_util.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/profile/cubit/edit_profile_cubit.dart';
import 'package:travibe/features/profile/cubit/profile_cubit.dart';
import 'package:travibe/features/profile/cubit/profile_picture_upload_cubit.dart';
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

/// Sets avatar_url when a picture is attached, like the backend.
class _AvatarRepo extends EditingRepo {
  static const url = 'https://example.invalid/new-avatar.png';
  bool attached = false;
  @override
  Future<void> updateProfile(ProfileUpdate update) async {
    await super.updateProfile(update);
    attached |= update.toJson().containsKey('avatar_media_id');
    if (attached) {
      result = ProfileModel.fromJson({
        ...profileJson(name: result!.name ?? 'Mona Hassan'),
        'avatar_url': url,
      });
    }
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
    final media = upload ?? _Upload();
    final pictures = ProfilePictureUploadCubit(uploads: () => media);
    final result = EditProfileCubit(
      owner,
      avatarRepo: photos,
      pictures: pictures,
    );
    addTearDown(() async {
      await result.close();
      await pictures.close();
      await owner.close();
    });
    return result;
  }

  /// Lets the background upload and attach run to completion.
  Future<void> settle(EditProfileCubit cubit) async {
    await Future<void>.delayed(Duration.zero);
    await cubit.pictures.settled();
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
    'picking uploads right away and saves only avatar_media_id to the profile',
    () async {
      final repo = _AvatarRepo();
      final upload = _Upload();
      final cubit = await editor(
        _Photos()..result = _photo(),
        repo: repo,
        upload: upload,
      );
      await cubit.pickAvatar();
      expect(cubit.pictures.state, isA<ProfilePictureUploading>());
      expect(cubit.pictures.state.preview, _bytes());
      await settle(cubit);
      expect(upload.calls, 1);
      expect(repo.writes.single, {'avatar_media_id': 77});
      expect(cubit.pictures.state, isA<ProfilePictureDone>());
      expect(cubit.pictures.state.preview, _bytes());
      expect(
        (cubit.owner.state as ProfileLoaded).profile.avatarUrl,
        _AvatarRepo.url,
      );
      // The picture is not an unsaved form change.
      expect(await cubit.save(ProfileDraft(profile())), false);
      expect(repo.writes, hasLength(1));
    },
  );

  test('cancelled or failed selection never starts an upload', () async {
    final photos = _Photos();
    final upload = _Upload();
    final cubit = await editor(photos, upload: upload);
    final original = (cubit.owner.state as ProfileLoaded).profile;
    await cubit.pickAvatar();
    photos.error = const InvalidProfileAvatar();
    await cubit.pickAvatar();
    expect(cubit.state.avatarError, contains('valid image'));
    expect(cubit.pictures.state, isA<ProfilePictureIdle>());
    expect(upload.calls, 0);
    expect((cubit.owner.state as ProfileLoaded).profile, same(original));
  });

  test('busy selection prevents duplicate picks and saves', () async {
    final photos = _Photos()..pending = Completer();
    final repo = EditingRepo();
    final cubit = await editor(photos, repo: repo);
    final draft = ProfileDraft(profile())..set('bio', 'Keep draft');
    final selecting = cubit.pickAvatar();
    expect(cubit.state.selectingAvatar, true);
    await cubit.pickAvatar();
    expect(await cubit.save(draft), false);
    expect(photos.calls, 1);
    photos.pending!.complete(null);
    await selecting;
    expect(await cubit.save(draft), true);
    expect(repo.writes.single, {'bio': 'Keep draft'});
    expect(cubit.state.saved, true);
    expect(draft.isDirty, false);
  });

  test(
    'Save Changes waits for the picture, then saves fields separately',
    () async {
      final repo = _AvatarRepo();
      final upload = _Upload()..pending = Completer<int>();
      final cubit = await editor(
        _Photos()..result = _photo(),
        repo: repo,
        upload: upload,
      );
      await cubit.pickAvatar();
      final draft = ProfileDraft(profile())..set('bio', 'Changed');
      final saving = cubit.save(draft);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.saving, true);
      expect(repo.writes, isEmpty);
      upload.pending!.complete(77);
      expect(await saving, true);
      expect(repo.writes, [
        {'avatar_media_id': 77},
        {'bio': 'Changed'},
      ]);
      expect(
        (cubit.owner.state as ProfileLoaded).profile.avatarUrl,
        _AvatarRepo.url,
      );
    },
  );

  test(
    'failed picture blocks Save; Retry re-attaches without re-uploading',
    () async {
      final repo = EditingRepo()..saveError = ApiError(message: 'Nope');
      final upload = _Upload();
      final cubit = await editor(
        _Photos()..result = _photo(),
        repo: repo,
        upload: upload,
      );
      await cubit.pickAvatar();
      await settle(cubit);
      expect(cubit.pictures.state, isA<ProfilePictureFailed>());
      expect(cubit.pictures.state.preview, _bytes());
      repo.saveError = null;
      final draft = ProfileDraft(profile())..set('bio', 'Unsaved');
      expect(await cubit.save(draft), false);
      expect(cubit.state.error?.message, contains('picture'));
      expect(repo.writes, hasLength(1)); // Only the failed attach.
      expect(draft.changes, {'bio': 'Unsaved'});
      await cubit.pictures.retry();
      expect(cubit.pictures.state, isA<ProfilePictureDone>());
      expect(upload.calls, 1); // Reuses the uploaded media ID.
      expect(repo.writes.last, {'avatar_media_id': 77});
      expect(await cubit.save(draft), true);
      expect(repo.writes.last, {'bio': 'Unsaved'});
    },
  );

  test(
    'upload failure retries the upload; X discards and unblocks Save',
    () async {
      final repo = EditingRepo();
      final upload = _Upload()..error = ApiError(message: 'Upload failed');
      final cubit = await editor(
        _Photos()..result = _photo(),
        repo: repo,
        upload: upload,
      );
      await cubit.pickAvatar();
      await settle(cubit);
      expect(cubit.pictures.state, isA<ProfilePictureFailed>());
      expect(repo.writes, isEmpty);
      await cubit.pictures.retry();
      expect(upload.calls, 2);
      expect(cubit.pictures.state, isA<ProfilePictureFailed>());
      cubit.pictures.discard();
      expect(cubit.pictures.state, isA<ProfilePictureIdle>());
      expect(cubit.pictures.state.preview, isNull);
      expect(
        await cubit.save(ProfileDraft(profile())..set('bio', 'Changed')),
        true,
      );
      expect(repo.writes.single, {'bio': 'Changed'});
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

  test('failed 401/422 saves preserve draft, errors and retry', () async {
    for (final code in [401, 422]) {
      final failure = ApiError(
        message: 'Cannot save',
        statusCode: code,
        fieldErrors: {
          'username': ['Already taken'],
        },
      );
      final repo = EditingRepo()..saveError = failure;
      final cubit = await editor(_Photos(), repo: repo);
      final draft = ProfileDraft(profile())..set('username', 'different_name');
      expect(await cubit.save(draft), false);
      expect(cubit.state.error, same(failure));
      expect(draft.changes, {'username': 'different_name'});
      repo.saveError = null;
      expect(await cubit.save(draft), true);
      expect(draft.isDirty, false);
    }
  });

  test(
    'saves prevent duplicates and do not restore stale session state',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = PreferencesManager();
      await prefs.init();
      await prefs.saveToken('test-save-owner-a');
      final repo = EditingRepo()..pending = Completer<void>();
      final cubit = await editor(_Photos(), repo: repo);
      final draft = ProfileDraft(profile())..set('bio', 'Changed');
      final saving = cubit.save(draft);
      expect(cubit.state.saving, true);
      expect(await cubit.save(draft), false);
      await Future<void>.delayed(Duration.zero);
      expect(repo.writes, hasLength(1));
      await prefs.saveToken('test-save-owner-b');
      repo.pending!.complete();
      expect(await saving, false);
      expect(cubit.state.sessionChanged, true);
      expect(cubit.state.saved, false);
      expect(draft.isDirty, true);
      await prefs.clear();
    },
  );

  test('disposed editor does not acknowledge a late field save', () async {
    final repo = EditingRepo()..pending = Completer<void>();
    final owner = ProfileCubit(profileRepo: repo);
    await owner.loadProfile();
    final cubit = EditProfileCubit(owner, avatarRepo: _Photos());
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
  });

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
    'session change during upload resets the picture and never PATCHes',
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
      expect(cubit.pictures.uploading, true);
      await prefs.saveToken('test-upload-b');
      expect(cubit.pictures.state, isA<ProfilePictureIdle>());
      upload.pending!.complete(77);
      await Future<void>.delayed(Duration.zero);
      expect(repo.writes, isEmpty);
      expect(cubit.state.sessionChanged, true);
      expect(cubit.pictures.state, isA<ProfilePictureIdle>());
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

  test('permission/plugin/platform errors are safe and recoverable', () async {
    final photos = _Photos();
    final cubit = await editor(photos);
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
      expect(cubit.state.selectingAvatar, false);
      expect(cubit.state.avatarError, isNotNull);
      expect(cubit.state.avatarError, isNot(contains('sensitive')));
      expect(cubit.state.avatarError, isNot(contains('private path')));
    }
    photos.error = null;
    await cubit.pickAvatar();
    expect(cubit.state.avatarError, isNull);
  });

  test('account changes reject pending selections and later saves', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesManager();
    await prefs.init();
    await prefs.saveToken('test-account-a');
    final photos = _Photos()..pending = Completer();
    final repo = EditingRepo();
    final upload = _Upload();
    final cubit = await editor(photos, repo: repo, upload: upload);
    final selecting = cubit.pickAvatar();
    await prefs.saveToken('test-account-b');
    expect(cubit.state.sessionChanged, true);
    photos.pending!.complete(_photo());
    await selecting;
    await cubit.pickAvatar();
    expect(photos.calls, 1);
    expect(upload.calls, 0);
    expect(
      await cubit.save(ProfileDraft(profile())..set('bio', 'Changed')),
      false,
    );
    expect(repo.writes, isEmpty);
    await prefs.clear();
  });

  test('a changed owner identity cannot receive a stale local photo', () async {
    final photos = _Photos()..pending = Completer();
    final repo = EditingRepo();
    final upload = _Upload();
    final cubit = await editor(photos, repo: repo, upload: upload);
    final selecting = cubit.pickAvatar();
    repo.result = profile(id: 8);
    await cubit.owner.refresh();
    photos.pending!.complete(_photo());
    await selecting;
    expect(upload.calls, 0);
    expect(cubit.pictures.state, isA<ProfilePictureIdle>());
    expect(cubit.state.sessionChanged, true);
    expect((cubit.owner.state as ProfileLoaded).profile.id, '8');
  });

  test(
    'disposed editor rejects pending photo and public profile cannot select',
    () async {
      final photos = _Photos()..pending = Completer();
      final owner = ProfileCubit(profileRepo: EditingRepo());
      await owner.loadProfile();
      final pictures = ProfilePictureUploadCubit(uploads: _Upload.new);
      addTearDown(pictures.close);
      final cubit = EditProfileCubit(
        owner,
        avatarRepo: photos,
        pictures: pictures,
      );
      final selecting = cubit.pickAvatar();
      await cubit.close();
      photos.pending!.complete(_photo());
      await selecting;
      expect(pictures.state, isA<ProfilePictureIdle>());
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
    ProfilePictureUploadCubit? pictures,
  }) async {
    final owner = ProfileCubit(profileRepo: repo);
    await owner.loadProfile();
    addTearDown(owner.close);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      withScreenUtil(
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
                      pictureUploads: pictures,
                      mediaUpload: upload ?? _Upload(),
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
    return owner;
  }

  Finder avatar() => find.byKey(const ValueKey('edit-profile-avatar'));
  Finder pick() => find.byKey(const ValueKey('pick-profile-avatar'));
  Finder save() => find.byType(ElevatedButton);
  const uploadingText = 'Uploading your picture';
  const successText = 'Picture updated successfully';
  const failureText = 'Couldn’t upload your picture';

  // The uploading toast's spinner never settles.
  Future<void> pumpUploading(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets(
    'upload shows the floating toast, no loading line, and the form stays usable',
    (tester) async {
      final photos = _Photos()..result = _photo();
      final upload = _Upload()..pending = Completer<int>();
      final repo = _AvatarRepo();
      await show(tester, photos, repo, upload: upload);
      expect(tester.widget<ElevatedButton>(save()).onPressed, isNull);
      await tester.tap(pick());
      await pumpUploading(tester);
      expect(find.text(uploadingText), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        tester.widget<CircleAvatar>(avatar()).backgroundImage,
        isA<MemoryImage>(),
      );
      // Usable while uploading; the picture alone is not a form change.
      expect(tester.widget<ElevatedButton>(save()).onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('full_name')),
        'Typing during upload',
      );
      await pumpUploading(tester);
      expect(find.text('Typing during upload'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(save()).onPressed, isNotNull);
      upload.pending!.complete(77);
      await tester.pumpAndSettle();
      expect(repo.writes.single, {'avatar_media_id': 77});
      expect(find.text(uploadingText), findsNothing);
      expect(find.text(successText), findsOneWidget);
      // Keeps the local picture after success (no flicker to network).
      expect(
        tester.widget<CircleAvatar>(avatar()).backgroundImage,
        isA<MemoryImage>(),
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text(successText), findsNothing);
    },
  );

  testWidgets(
    'Edit Profile uses the Setup dashed orange 128 ring and the whole circle picks',
    (tester) async {
      final photos = _Photos()..result = _photo();
      final upload = _Upload()..pending = Completer<int>();
      await show(tester, photos, _AvatarRepo(), upload: upload);
      final ring = find.ancestor(
        of: avatar(),
        matching: find.byType(DottedBorder),
      );
      final border = tester.widget<DottedBorder>(ring);
      expect(border.options, isA<CircularDottedBorderOptions>());
      expect(border.options.color, const Color(0xFFE45C10));
      expect(tester.getSize(ring), const Size(128, 128));
      expect(tester.getSize(pick()), const Size(32, 32));
      await tester.tap(avatar());
      await pumpUploading(tester);
      expect(find.text(uploadingText), findsOneWidget);
      upload.pending!.complete(5);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('failure shows red toast with Retry and X', (tester) async {
    final photos = _Photos()..result = _photo();
    final upload = _Upload()..error = ApiError(message: 'Upload failed');
    final repo = EditingRepo();
    await show(tester, photos, repo, upload: upload);
    await tester.tap(pick());
    await tester.pumpAndSettle();
    expect(find.text(failureText), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byTooltip('Dismiss'), findsOneWidget);
    upload.error = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(upload.calls, 2);
    expect(repo.writes.single, {'avatar_media_id': 77});
    expect(find.text(failureText), findsNothing);
    expect(find.text(successText), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('X dismisses a failed picture and restores the old avatar', (
    tester,
  ) async {
    final photos = _Photos()..result = _photo();
    final upload = _Upload()..error = ApiError(message: 'Upload failed');
    await show(tester, photos, EditingRepo(), upload: upload);
    await tester.tap(pick());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text(failureText), findsNothing);
    expect(tester.widget<CircleAvatar>(avatar()).backgroundImage, isNull);
  });

  testWidgets(
    'Save Changes waits for the picture upload, then saves and closes',
    (tester) async {
      final photos = _Photos()..result = _photo();
      final upload = _Upload()..pending = Completer<int>();
      final repo = _AvatarRepo();
      await show(tester, photos, repo, upload: upload);
      await tester.tap(pick());
      await pumpUploading(tester);
      await tester.enterText(
        find.byKey(const ValueKey('full_name')),
        'Updated name',
      );
      await tester.pump();
      await tester.tap(save());
      await pumpUploading(tester);
      expect(tester.widget<ElevatedButton>(save()).onPressed, isNull);
      expect(repo.writes, isEmpty);
      upload.pending!.complete(77);
      await tester.pumpAndSettle();
      expect(repo.writes, [
        {'avatar_media_id': 77},
        {'full_name': 'Updated name'},
      ]);
      expect(find.text('Open editor'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'leaving mid-upload needs no discard prompt and the upload continues',
    (tester) async {
      final photos = _Photos()..result = _photo();
      final upload = _Upload()..pending = Completer<int>();
      final repo = _AvatarRepo();
      final pictures = ProfilePictureUploadCubit(uploads: () => upload);
      addTearDown(pictures.close);
      final owner = await show(tester, photos, repo, pictures: pictures);
      await tester.tap(pick());
      await pumpUploading(tester);
      await tester.pageBack();
      for (var i = 0; i < 4; i++) {
        await pumpUploading(tester);
      }
      expect(find.byType(EditProfileScreen), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Open editor'), findsOneWidget);
      expect(find.text(uploadingText), findsNothing); // Root shows its own.
      upload.pending!.complete(77);
      await tester.pumpAndSettle();
      expect(pictures.state, isA<ProfilePictureDone>());
      expect(repo.writes.single, {'avatar_media_id': 77});
      expect((owner.state as ProfileLoaded).profile.avatarUrl, _AvatarRepo.url);
    },
  );

  testWidgets(
    'pending picker shows no loading line and cancellation keeps avatar',
    (tester) async {
      final photos = _Photos()..pending = Completer();
      await show(tester, photos, EditingRepo());
      await tester.tap(pick());
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.tap(pick(), warnIfMissed: false);
      expect(photos.calls, 1);
      photos.pending!.complete(null);
      await tester.pumpAndSettle();
      expect(tester.widget<CircleAvatar>(avatar()).backgroundImage, isNull);
      expect(find.text(uploadingText), findsNothing);
      expect(find.text('Mona Hassan'), findsOneWidget);
    },
  );

  testWidgets(
    'picker failure displays error and retains typed fields without HTTP',
    (tester) async {
      final photos = _Photos();
      final repo = EditingRepo();
      var requests = 0;
      await HttpOverrides.runZoned(
        () async {
          await show(tester, photos, repo);
          await tester.enterText(
            find.byKey(const ValueKey('username')),
            'keep_name',
          );
          photos.error = PlatformException(code: 'photo_access_denied');
          await tester.tap(pick());
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('avatar-error')), findsOneWidget);
          expect(find.text(failureText), findsNothing);
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

  testWidgets('session changes hide old fields while late picker is ignored', (
    tester,
  ) async {
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
    expect(find.text(uploadingText), findsNothing);
    await tester.runAsync(() => PreferencesManager().clear());
  });
}
