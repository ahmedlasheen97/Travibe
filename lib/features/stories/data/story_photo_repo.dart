import 'dart:ui' as ui;

import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/features/stories/data/story_editor_draft.dart';

abstract class StoryPendingSelectionStore {
  Future<bool> get isPending;
  Future<void> setPending(bool pending);
}

class StoryPreferencesSelectionStore implements StoryPendingSelectionStore {
  static const _key = 'story_photo_picker_pending';

  @override
  Future<bool> get isPending async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  @override
  Future<void> setPending(bool pending) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = pending
        ? await preferences.setBool(_key, true)
        : await preferences.remove(_key);
    if (!saved) throw StateError('Unable to persist picker ownership.');
  }
}

class InvalidStoryImage implements Exception {
  const InvalidStoryImage();
}

/// Local photo access only; no API client, upload, or publication dependency.
class StoryPhotoRepo {
  StoryPhotoRepo({
    ImagePicker? picker,
    StoryPendingSelectionStore? pendingStore,
  }) : _picker = picker ?? ImagePicker(),
       _pending = pendingStore ?? StoryPreferencesSelectionStore();

  final ImagePicker _picker;
  final StoryPendingSelectionStore _pending;

  Future<StoryEditorDraft?> pick() => _select(ImageSource.gallery);

  Future<StoryEditorDraft?> capture() => _select(ImageSource.camera);

  Future<StoryEditorDraft?> _select(ImageSource source) async {
    await _pending.setPending(true);
    final platform = ImagePickerPlatform.instance;
    final android =
        source == ImageSource.gallery && platform is ImagePickerAndroid
        ? platform
        : null;
    final previousPhotoPicker = android?.useAndroidPhotoPicker;
    try {
      // The locked Android implementation requires opt-in below Android 16.
      // Restore its setting afterwards so other features keep their behavior.
      if (android != null) android.useAndroidPhotoPicker = true;
      final file = await _picker.pickImage(
        source: source,
        requestFullMetadata: false,
      );
      return file == null ? null : await _draft(file);
    } finally {
      if (android != null) {
        android.useAndroidPhotoPicker = previousPhotoPicker!;
      }
      await _pending.setPending(false);
    }
  }

  Future<StoryEditorDraft?> recover() async {
    // image_picker's lost-data cache is shared by all features.
    if (!await _pending.isPending) return null;
    try {
      final response = await _picker.retrieveLostData();
      if (response.exception != null) throw response.exception!;
      final files = response.files;
      if (files == null || files.isEmpty) return null;
      if (files.length != 1 || response.type != RetrieveType.image) {
        throw const InvalidStoryImage();
      }
      return await _draft(files.single);
    } finally {
      await _pending.setPending(false);
    }
  }

  Future<StoryEditorDraft> _draft(XFile file) async {
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) throw const InvalidStoryImage();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      ui.ImageDescriptor? descriptor;
      ui.Codec? codec;
      try {
        descriptor = await ui.ImageDescriptor.encoded(buffer);
        if (descriptor.width <= 0 || descriptor.height <= 0) {
          throw const InvalidStoryImage();
        }
        // Validate decoding without allocating a full-size validation bitmap.
        codec = await descriptor.instantiateCodec(
          targetWidth: 1,
          targetHeight: 1,
        );
        final frame = await codec.getNextFrame();
        frame.image.dispose();
        return StoryEditorDraft(
          image: StorySourceImage(
            path: file.path,
            name: file.name,
            width: descriptor.width,
            height: descriptor.height,
            bytes: bytes,
          ),
        );
      } finally {
        codec?.dispose();
        descriptor?.dispose();
        buffer.dispose();
      }
    } catch (_) {
      throw const InvalidStoryImage();
    }
  }
}
