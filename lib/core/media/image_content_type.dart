import 'dart:typed_data';

/// Image MIME types the media API accepts for posts, comments and stories.
const uploadableImageTypes = {
  'image/jpeg',
  'image/png',
  'image/gif',
  'image/webp',
};

/// Per-type image size limit enforced by `POST /media/presign`.
const maxUploadImageBytes = 20 * 1024 * 1024;

/// Detects an image MIME type from its bytes, never from the filename.
String? sniffImageContentType(Uint8List bytes) {
  bool starts(List<int> signature) {
    if (bytes.length < signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) return false;
    }
    return true;
  }

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
