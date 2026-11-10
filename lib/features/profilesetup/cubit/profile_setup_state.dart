part of 'profile_setup_cubit.dart';

enum ProfileSetupStatus { editing, saving, completed, failure }

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
  final File? avatarFile;
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
    this.avatarFile,
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
    File? avatarFile,
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
      currentLocation: currentLocation ?? this.currentLocation,
      avatarFile: avatarFile ?? this.avatarFile,
      languages: languages ?? this.languages,
      interests: interests ?? this.interests,
      travelStyles: travelStyles ?? this.travelStyles,
      result: result ?? this.result,
    );
  }
}
