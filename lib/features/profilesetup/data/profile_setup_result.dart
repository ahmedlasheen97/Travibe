import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/profile/data/profile_model.dart';

enum ProfileSetupStep {
  identity('identity', 0),
  languagesInterests('languages_interests', 1),
  travelStyle('travel_style', 2),
  review('review', 2),
  complete('complete', 2);

  const ProfileSetupStep(this.value, this.page);
  final String value;
  final int page;
}

class ProfileSetupResult {
  const ProfileSetupResult._({
    required this.profileCompleted,
    required this.step,
    this.profile,
    this.resourceFields = const {},
  });
  final bool profileCompleted;
  final ProfileSetupStep step;
  final ProfileModel? profile;
  final Set<String> resourceFields;

  factory ProfileSetupResult.fromJson(dynamic json) =>
      _parse(json, readProfile: true);

  // The existing completion endpoint's metadata is documented independently of
  // its resource envelope. Do not assume its data is the PATCH UserResource.
  factory ProfileSetupResult.completion(dynamic json) =>
      _parse(json, readProfile: false);

  static ProfileSetupResult _parse(dynamic json, {required bool readProfile}) {
    final meta = json is Map ? json['meta'] : null;
    if (meta is! Map || meta['profile_completed'] is! bool) throw _invalid();
    final step = ProfileSetupStep.values
        .where((item) => item.value == meta['profile_setup_step'])
        .firstOrNull;
    if (step == null) throw _invalid();
    ProfileModel? profile;
    Set<String> fields = const {};
    if (readProfile) {
      final data = json['data'];
      if (data is! Map<String, dynamic>) throw _invalid();
      profile = ProfileModel.fromJson(data);
      fields = Set.unmodifiable(data.keys);
    }
    return ProfileSetupResult._(
      profileCompleted: meta['profile_completed'] as bool,
      step: step,
      profile: profile,
      resourceFields: fields,
    );
  }

  static ApiError _invalid() => ApiError(
    message: 'Unable to read the profile setup response. Please try again.',
  );
}
