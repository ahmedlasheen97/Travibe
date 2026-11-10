import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

/// Local selection. A media ID is assigned only by the verified upload pipeline.
class ProfileAvatarDraft {
  ProfileAvatarDraft({required this.name, required Uint8List bytes})
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView();

  final String name;
  final Uint8List bytes;

  /// Inspect bytes rather than trusting a filename or picker-supplied MIME.
  String? get contentType {
    bool starts(List<int> signature) =>
        bytes.length >= signature.length &&
        List.generate(
          signature.length,
          (i) => bytes[i] == signature[i],
        ).every((v) => v);
    if (starts([137, 80, 78, 71, 13, 10, 26, 10])) return 'image/png';
    if (starts([255, 216, 255])) return 'image/jpeg';
    if (starts([71, 73, 70, 56, 55, 97]) || starts([71, 73, 70, 56, 57, 97])) {
      return 'image/gif';
    }
    if (starts([82, 73, 70, 70]) &&
        bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return 'image/webp';
    }
    return null;
  }
}

class InvalidProfileAvatar implements Exception {
  const InvalidProfileAvatar();
}

/// Single native gallery selection, using the same picker options as Stories.
/// Uploading remains a separate, explicit Save action.
class ProfileAvatarRepo {
  ProfileAvatarRepo({ImagePicker? picker}) : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;

  Future<ProfileAvatarDraft?> pick() async {
    final platform = ImagePickerPlatform.instance;
    final android = platform is ImagePickerAndroid ? platform : null;
    final previousPhotoPicker = android?.useAndroidPhotoPicker;
    XFile? file;
    try {
      if (android != null) android.useAndroidPhotoPicker = true;
      file = await _picker.pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );
    } finally {
      if (android != null) android.useAndroidPhotoPicker = previousPhotoPicker!;
    }
    if (file == null) return null;
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) throw const InvalidProfileAvatar();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      ui.ImageDescriptor? descriptor;
      ui.Codec? codec;
      try {
        descriptor = await ui.ImageDescriptor.encoded(buffer);
        if (descriptor.width <= 0 || descriptor.height <= 0) {
          throw const InvalidProfileAvatar();
        }
        codec = await descriptor.instantiateCodec(
          targetWidth: 1,
          targetHeight: 1,
        );
        final frame = await codec.getNextFrame();
        frame.image.dispose();
        final draft = ProfileAvatarDraft(name: file.name, bytes: bytes);
        if (draft.contentType == null) throw const InvalidProfileAvatar();
        return draft;
      } finally {
        codec?.dispose();
        descriptor?.dispose();
        buffer.dispose();
      }
    } catch (_) {
      throw const InvalidProfileAvatar();
    }
  }
}
