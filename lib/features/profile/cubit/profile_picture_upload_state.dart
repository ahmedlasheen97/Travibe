part of 'profile_picture_upload_cubit.dart';

sealed class ProfilePictureUploadState {
  const ProfilePictureUploadState();

  /// The picked photo's bytes, shown locally while and after uploading.
  Uint8List? get preview => null;
}

final class ProfilePictureIdle extends ProfilePictureUploadState {
  const ProfilePictureIdle();
}

final class ProfilePictureUploading extends ProfilePictureUploadState {
  const ProfilePictureUploading(this.preview, {this.progress = .1});
  @override
  final Uint8List preview;

  /// 0.1..1 for the toast's white progress ring.
  final double progress;
}

final class ProfilePictureFailed extends ProfilePictureUploadState {
  const ProfilePictureFailed(this.preview);
  @override
  final Uint8List preview;
}

/// Uploaded and ready; saved to the profile only by Save Changes.
final class ProfilePictureDone extends ProfilePictureUploadState {
  const ProfilePictureDone(this.preview, {required this.mediaId});
  @override
  final Uint8List preview;
  final int mediaId;
}
