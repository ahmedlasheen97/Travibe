import 'dart:typed_data';

/// A locally selected post photo. [mediaId] is set once the bytes have been
/// uploaded and finalized, so a retry never uploads the same photo twice.
class PostImage {
  const PostImage({
    required this.localId,
    required this.bytes,
    required this.filename,
    required this.contentType,
    this.mediaId,
  });

  final String localId;
  final Uint8List bytes;
  final String filename;
  final String contentType;
  final int? mediaId;

  PostImage withMediaId(int id) => PostImage(
    localId: localId,
    bytes: bytes,
    filename: filename,
    contentType: contentType,
    mediaId: id,
  );
}
