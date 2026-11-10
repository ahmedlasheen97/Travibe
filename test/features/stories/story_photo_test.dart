import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/features/stories/cubit/story_picker_cubit.dart';
import 'package:travibe/features/stories/data/story_photo_repo.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SpyImagePicker picker;
  late MemoryPendingStore pending;
  late StoryPhotoRepo repo;
  setUp(() {
    picker = SpyImagePicker();
    pending = MemoryPendingStore();
    repo = StoryPhotoRepo(picker: picker, pendingStore: pending);
  });

  test(
    'single image gallery selection disables full metadata and leaves source untouched',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'story-photo-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final source = await File(
        '${directory.path}/original.png',
      ).writeAsBytes(photoBytes());
      picker.result = XFile(source.path);
      picker.onPick = () => expect(pending.pending, isTrue);
      final selected = (await repo.pick())!;
      expect(picker.picks, 1);
      expect(picker.source, ImageSource.gallery);
      expect(picker.fullMetadata, isFalse);
      expect(picker.width, isNull);
      expect(picker.height, isNull);
      expect(picker.quality, isNull);
      expect(selected.image.path, source.path);
      expect(selected.image.width, 4);
      expect(selected.image.height, 2);
      expect(selected.layers, isEmpty);
      expect(await source.readAsBytes(), photoBytes());
      expect(pending.pending, isFalse);
      await source.delete();
      expect(selected.image.bytes, photoBytes());
      expect(() => selected.image.bytes[0] = 0, throwsUnsupportedError);
      expect(() => selected.layers.clear(), throwsUnsupportedError);
    },
  );

  test('cancellation returns no draft and clears the marker', () async {
    expect(await repo.pick(), isNull);
    expect(pending.pending, isFalse);
  });

  test(
    'camera captures one image with shared validation and unchanged source bytes',
    () async {
      picker.result = XFile.fromData(photoBytes(), name: 'camera.png');
      picker.onPick = () => expect(pending.pending, isTrue);
      final captured = (await repo.capture())!;
      expect(picker.picks, 1);
      expect(picker.source, ImageSource.camera);
      expect(picker.fullMetadata, isFalse);
      expect(picker.width, isNull);
      expect(picker.height, isNull);
      expect(picker.quality, isNull);
      expect(captured.image.bytes, photoBytes());
      expect(captured.image.width, 4);
      expect(captured.image.height, 2);
      expect(captured.layers, isEmpty);
      expect(pending.pending, isFalse);
    },
  );

  test('camera cancellation clears ownership without a draft', () async {
    expect(await repo.capture(), isNull);
    expect(picker.source, ImageSource.camera);
    expect(pending.pending, isFalse);
  });

  test(
    'camera rejects empty, invalid and unreadable images through gallery validator',
    () async {
      for (final file in [
        XFile.fromData(Uint8List(0)),
        XFile.fromData(Uint8List.fromList([1, 2, 3])),
        XFile('/missing/camera.png'),
      ]) {
        picker.result = file;
        await expectLater(repo.capture(), throwsA(isA<InvalidStoryImage>()));
        expect(pending.pending, isFalse);
      }
    },
  );

  test(
    'camera leaves Android gallery Photo Picker configuration unchanged',
    () async {
      final previous = ImagePickerPlatform.instance;
      final android = ImagePickerAndroid();
      ImagePickerPlatform.instance = android;
      addTearDown(() => ImagePickerPlatform.instance = previous);
      for (final enabled in [false, true]) {
        android.useAndroidPhotoPicker = enabled;
        picker.onPick = () => expect(android.useAndroidPhotoPicker, enabled);
        await repo.capture();
        expect(android.useAndroidPhotoPicker, enabled);
      }
    },
  );

  test(
    'duplicate camera, gallery and recovery operations cannot overlap',
    () async {
      picker.completer = Completer<XFile?>();
      final cubit = StoryPickerCubit(repo: repo);
      addTearDown(cubit.close);
      final first = cubit.capture();
      expect(cubit.state.busy, isTrue);
      expect(cubit.state.capturing, isTrue);
      expect(await cubit.capture(), isNull);
      expect(await cubit.pick(), isNull);
      expect(await cubit.recover(), isNull);
      picker.completer!.complete(null);
      await first;
      expect(picker.picks, 1);
      expect(picker.recoveries, 0);
      expect(cubit.state.busy, isFalse);
      expect(cubit.state.capturing, isFalse);
    },
  );

  test(
    'camera completion after Cubit disposal cannot return a draft',
    () async {
      final stub = StubStoryPhotoRepo()..selection = Completer();
      final cubit = StoryPickerCubit(repo: stub);
      final capture = cubit.capture();
      await cubit.close();
      stub.selection!.complete(draft());
      expect(await capture, isNull);
    },
  );

  final cameraErrors = <Object, String>{
    PlatformException(code: 'camera_access_denied'):
        'Camera access is restricted. Check your device settings.',
    PlatformException(code: 'camera_access_restricted'):
        'Camera access is restricted. Check your device settings.',
    PlatformException(code: 'no_available_camera'):
        'The camera is unavailable on this device.',
    MissingPluginException(): 'The camera is unavailable on this device.',
    UnsupportedError('private details'):
        'The camera is unavailable on this device.',
    PlatformException(code: 'unknown', message: 'private details'):
        'Unable to take a photo. Please try again.',
  };
  for (final entry in cameraErrors.entries) {
    test(
      'camera error ${entry.key} is safe, clears marker and permits retry',
      () async {
        picker.error = entry.key;
        final cubit = StoryPickerCubit(repo: repo);
        addTearDown(cubit.close);
        expect(await cubit.capture(), isNull);
        expect(cubit.state.error, entry.value);
        expect(cubit.state.error, isNot(contains('private details')));
        expect(cubit.state.busy, isFalse);
        expect(pending.pending, isFalse);
        picker.error = null;
        expect(await cubit.capture(), isNull);
        expect(cubit.state.error, isNull);
      },
    );
  }

  for (final bytes in [
    Uint8List(0),
    Uint8List.fromList([1, 2, 3, 4]),
  ]) {
    test('invalid image (${bytes.length} bytes) is rejected', () async {
      picker.result = XFile.fromData(bytes, name: 'not-an-image.png');
      await expectLater(repo.pick(), throwsA(isA<InvalidStoryImage>()));
      expect(pending.pending, isFalse);
    });
  }

  test('unreadable local file is rejected', () async {
    picker.result = XFile('/missing/story-photo.png');
    await expectLater(repo.pick(), throwsA(isA<InvalidStoryImage>()));
    expect(pending.pending, isFalse);
  });

  test('Android photo picker is enabled only for Story selection', () async {
    final previous = ImagePickerPlatform.instance;
    final android = ImagePickerAndroid();
    ImagePickerPlatform.instance = android;
    addTearDown(() => ImagePickerPlatform.instance = previous);
    picker.onPick = () => expect(android.useAndroidPhotoPicker, isTrue);
    await repo.pick();
    expect(android.useAndroidPhotoPicker, isFalse);
    picker.error = PlatformException(code: 'picker_failed');
    await expectLater(repo.pick(), throwsA(isA<PlatformException>()));
    expect(android.useAndroidPhotoPicker, isFalse);
    expect(pending.pending, isFalse);
  });

  test('unowned Android lost data is not consumed', () async {
    expect(await repo.recover(), isNull);
    expect(picker.recoveries, 0);
  });

  test('owned Android image is recovered once', () async {
    pending.pending = true;
    picker.lost = LostDataResponse(
      type: RetrieveType.image,
      files: [XFile.fromData(photoBytes(), name: 'recovered.png')],
    );
    expect((await repo.recover())!.image.bytes, photoBytes());
    expect(pending.pending, isFalse);
    expect(await repo.recover(), isNull);
    expect(picker.recoveries, 1);
  });

  test('empty recovery clears stale ownership', () async {
    pending.pending = true;
    expect(await repo.recover(), isNull);
    expect(pending.pending, isFalse);
  });

  test('multiple recovered images and recovered videos are rejected', () async {
    for (final response in [
      LostDataResponse(
        type: RetrieveType.image,
        files: [XFile.fromData(photoBytes()), XFile.fromData(photoBytes())],
      ),
      LostDataResponse(
        type: RetrieveType.video,
        files: [XFile.fromData(photoBytes())],
      ),
    ]) {
      pending.pending = true;
      picker.lost = response;
      await expectLater(repo.recover(), throwsA(isA<InvalidStoryImage>()));
      expect(pending.pending, isFalse);
    }
  });

  test('recovery error is surfaced and clears ownership', () async {
    pending.pending = true;
    picker.lost = LostDataResponse(
      exception: PlatformException(code: 'lost_file'),
    );
    final cubit = StoryPickerCubit(repo: repo);
    addTearDown(cubit.close);
    expect(await cubit.recover(), isNull);
    expect(cubit.state.error, isNotEmpty);
    expect(pending.pending, isFalse);
  });

  test('pending ownership survives store recreation', () async {
    SharedPreferences.setMockInitialValues({});
    await StoryPreferencesSelectionStore().setPending(true);
    expect(await StoryPreferencesSelectionStore().isPending, isTrue);
    await StoryPreferencesSelectionStore().setPending(false);
    expect(await StoryPreferencesSelectionStore().isPending, isFalse);
  });

  test('duplicate picks and recovery cannot overlap', () async {
    picker.completer = Completer<XFile?>();
    final cubit = StoryPickerCubit(repo: repo);
    addTearDown(cubit.close);
    final first = cubit.pick();
    expect(cubit.state.busy, isTrue);
    expect(await cubit.pick(), isNull);
    expect(await cubit.recover(), isNull);
    picker.completer!.complete(null);
    await first;
    expect(picker.picks, 1);
    expect(picker.recoveries, 0);
    expect(cubit.state.busy, isFalse);
  });

  test(
    'late selection after disposal does not emit or return a draft',
    () async {
      final stub = StubStoryPhotoRepo()..selection = Completer();
      final cubit = StoryPickerCubit(repo: stub);
      final selection = cubit.pick();
      await cubit.close();
      stub.selection!.complete(draft());
      expect(await selection, isNull);
    },
  );

  for (final error in [
    MissingPluginException(),
    PlatformException(code: 'photo_access_denied'),
    PlatformException(code: 'unknown', message: 'sensitive native details'),
  ]) {
    test(
      'picker error ${error.runtimeType} produces safe feedback and allows retry',
      () async {
        picker.error = error;
        final cubit = StoryPickerCubit(repo: repo);
        addTearDown(cubit.close);
        expect(await cubit.pick(), isNull);
        expect(cubit.state.busy, isFalse);
        expect(cubit.state.error, isNotEmpty);
        expect(cubit.state.error, isNot(contains('sensitive')));
        expect(pending.pending, isFalse);
        picker.error = null;
        expect(await cubit.pick(), isNull);
        expect(cubit.state.error, isNull);
      },
    );
  }
}
