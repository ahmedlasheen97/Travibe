part of 'profile_setup_cubit.dart';

/// [skipped]: the user chose "Skip for now"; setup stays incomplete.
enum ProfileSetupStatus { editing, saving, completed, skipped, failure }

enum UsernameStatus { idle, checking, available, taken, invalid }

@immutable
class ProfileSetupState {
  final Map<ReferenceKind, ReferenceCatalog> catalogs;
  ReferenceCatalog catalog(ReferenceKind kind) =>
      catalogs[kind] ?? const ReferenceCatalog();
  final int step;
  final ProfileSetupStatus status;
  final String errorMessage;
  final UsernameStatus usernameStatus;
  final String usernameMessage;
  final String normalizedUsername;
  final String? currentLocation;
  final ProfileAvatarDraft? avatar;

  /// Bytes of the last uploaded photo, kept on screen after success so the
  /// avatar doesn't flicker back to a loading network image.
  final Uint8List? avatarPreview;

  /// The last upload failed; shown as a toast with Retry and X.
  final bool avatarUploadFailed;
  final String? avatarUrl;
  final String? avatarError;
  final bool selectingAvatar;
  final bool uploadingAvatar;
  final MediaUploadStage? avatarStage;

  /// 0.1..1 while uploading, for the toast's white progress ring.
  final double avatarProgress;
  final Map<String, List<String>> fieldErrors;
  final bool restoring;
  final String? restoreError;
  final List<String> languages;
  final List<String> interests;
  final List<String> travelStyles;
  final ProfileSetupResult? result;
  bool? get profileCompleted => result?.profileCompleted;
  ProfileSetupStep? get serverStep => result?.step;

  const ProfileSetupState({
    this.catalogs = const {},
    this.step = 0,
    this.status = ProfileSetupStatus.editing,
    this.errorMessage = '',
    this.usernameStatus = UsernameStatus.idle,
    this.usernameMessage = '',
    this.normalizedUsername = '',
    this.currentLocation,
    this.avatar,
    this.avatarPreview,
    this.avatarUploadFailed = false,
    this.avatarUrl,
    this.avatarError,
    this.selectingAvatar = false,
    this.uploadingAvatar = false,
    this.avatarStage,
    this.avatarProgress = 0,
    this.fieldErrors = const {},
    this.restoring = false,
    this.restoreError,
    this.languages = const [],
    this.interests = const [],
    this.travelStyles = const [],
    this.result,
  });

  bool get isSaving => status == ProfileSetupStatus.saving;

  ProfileSetupState copyWith({
    Map<ReferenceKind, ReferenceCatalog>? catalogs,
    int? step,
    ProfileSetupStatus? status,
    String? errorMessage,
    UsernameStatus? usernameStatus,
    String? usernameMessage,
    String? normalizedUsername,
    String? currentLocation,
    bool clearCurrentLocation = false,
    ProfileAvatarDraft? avatar,
    Uint8List? avatarPreview,
    bool? avatarUploadFailed,
    String? avatarUrl,
    String? avatarError,
    bool? selectingAvatar,
    bool? uploadingAvatar,
    MediaUploadStage? avatarStage,
    double? avatarProgress,
    bool clearAvatar = false,
    bool clearAvatarError = false,
    Map<String, List<String>>? fieldErrors,
    bool? restoring,
    String? restoreError,
    bool clearRestoreError = false,
    List<String>? languages,
    List<String>? interests,
    List<String>? travelStyles,
    ProfileSetupResult? result,
  }) {
    return ProfileSetupState(
      catalogs: catalogs ?? this.catalogs,
      step: step ?? this.step,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      usernameStatus: usernameStatus ?? this.usernameStatus,
      usernameMessage: usernameMessage ?? this.usernameMessage,
      normalizedUsername: normalizedUsername ?? this.normalizedUsername,
      currentLocation: clearCurrentLocation
          ? null
          : currentLocation ?? this.currentLocation,
      avatar: clearAvatar ? null : avatar ?? this.avatar,
      avatarPreview: avatarPreview ?? this.avatarPreview,
      avatarUploadFailed: avatarUploadFailed ?? this.avatarUploadFailed,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      avatarError: clearAvatarError ? null : avatarError ?? this.avatarError,
      selectingAvatar: selectingAvatar ?? this.selectingAvatar,
      uploadingAvatar: uploadingAvatar ?? this.uploadingAvatar,
      avatarStage: avatarStage ?? this.avatarStage,
      avatarProgress: avatarProgress ?? this.avatarProgress,
      fieldErrors: fieldErrors ?? this.fieldErrors,
      restoring: restoring ?? this.restoring,
      restoreError: clearRestoreError
          ? null
          : restoreError ?? this.restoreError,
      languages: languages ?? this.languages,
      interests: interests ?? this.interests,
      travelStyles: travelStyles ?? this.travelStyles,
      result: result ?? this.result,
    );
  }
}
