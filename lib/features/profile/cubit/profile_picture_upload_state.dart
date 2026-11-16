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
  const ProfilePictureUploading(this.preview);
  @override
  final Uint8List preview;
}

final class ProfilePictureFailed extends ProfilePictureUploadState {
  const ProfilePictureFailed(this.preview);
  @override
  final Uint8List preview;
}

final class ProfilePictureDone extends ProfilePictureUploadState {
  const ProfilePictureDone(this.preview);
  @override
  final Uint8List preview;
}
