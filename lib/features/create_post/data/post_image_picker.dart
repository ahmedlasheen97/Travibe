import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:travibe/core/media/image_content_type.dart';
import 'package:travibe/features/create_post/data/post_image.dart';

/// The user denied camera or photo access; the screen offers Settings.
class PostImagePermissionDenied implements Exception {
  const PostImagePermissionDenied({required this.camera});
  final bool camera;
}

/// Photos that were picked, plus how many were dropped and why.
class PostImagePick {
  const PostImagePick(this.images, {this.rejected = 0});
  final List<PostImage> images;
  final int rejected;
}

/// Local photo access only. Gallery uses the system picker (iOS PHPicker,
/// Android Photo Picker), which needs no permission. Large photos are
/// downscaled and re-encoded natively before they are read.
class PostImagePicker {
  PostImagePicker({ImagePicker? picker}) : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;
  var _sequence = 0;

  static const maxDimension = 2048.0;
  static const quality = 85;

  Future<PostImagePick> pickGallery({required int limit}) async {
    if (limit < 1) return const PostImagePick([]);
    final platform = ImagePickerPlatform.instance;
    final android = platform is ImagePickerAndroid ? platform : null;
    final previous = android?.useAndroidPhotoPicker;
    try {
      // The Android implementation requires opt-in below Android 16; restore
      // the shared setting afterwards so other features keep their behavior.
      if (android != null) android.useAndroidPhotoPicker = true;
      final files = await _picker.pickMultiImage(
        maxWidth: maxDimension,
        maxHeight: maxDimension,
        imageQuality: quality,
        limit: limit,
        requestFullMetadata: false,
      );
      return _read(files);
    } on PlatformException catch (error) {
      throw _mapped(error, camera: false);
    } finally {
      if (android != null) android.useAndroidPhotoPicker = previous!;
    }
  }

  Future<PostImagePick> capture() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: maxDimension,
        maxHeight: maxDimension,
        imageQuality: quality,
        requestFullMetadata: false,
      );
      return _read([?file]);
    } on PlatformException catch (error) {
      throw _mapped(error, camera: true);
    }
  }

  Object _mapped(PlatformException error, {required bool camera}) =>
      error.code == 'camera_access_denied' ||
          error.code == 'photo_access_denied'
      ? PostImagePermissionDenied(camera: error.code == 'camera_access_denied')
      : error;

  Future<PostImagePick> _read(List<XFile> files) async {
    final images = <PostImage>[];
    var rejected = 0;
    for (final file in files) {
      final bytes = await file.readAsBytes();
      final type = sniffImageContentType(bytes);
      if (bytes.isEmpty ||
          bytes.length > maxUploadImageBytes ||
          type == null ||
          !uploadableImageTypes.contains(type)) {
        rejected++;
        continue;
      }
      final extension = type.split('/').last.replaceFirst('jpeg', 'jpg');
      final id = '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
      images.add(
        PostImage(
          localId: id,
          bytes: bytes,
          filename: 'post-$id.$extension',
          contentType: type,
        ),
      );
    }
    return PostImagePick(images, rejected: rejected);
  }
}
