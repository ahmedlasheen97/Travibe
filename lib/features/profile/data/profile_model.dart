import 'package:travibe/core/datasource/remotedata/api_error.dart';

/// Profile responses are not fully described by the checked-in OpenAPI file.
/// Keep field-name/shape assumptions here, separate from API and UI behavior.
class ProfileReference {
  const ProfileReference({required this.slug, required this.name});
  final String slug;
  final String name;
}

class ProfileModel {
  const ProfileModel({
    required this.id,
    this.name,
    this.username,
    this.email,
    this.locale,
    this.currencyCode,
    this.showActiveStatus,
    this.showInTravelBuddy,
    this.pushNotificationsEnabled,
    this.settingsIncluded = false,
    this.emailVerifiedAt,
    this.termsAcceptedAt,
    this.profileCompletedAt,
    this.profileCompleted,
    this.createdAt,
    this.updatedAt,
    this.avatarUrl,
    this.bio,
    this.countryCode,
    this.currentLocation,
    this.locationIncluded = false,
    this.nationality,
    this.nationalityCode,
    this.gender,
    this.languageSelections = const [],
    this.interestSelections = const [],
    this.travelStyleSelections = const [],
    this.postsCount,
    this.followersCount,
    this.followingCount,
    this.isMe,
    this.isFollowing,
    this.followsYou,
    this.isBlocked,
  });

  final String id;
  final String? name;
  final String? username;
  final String? email;
  final String? locale;
  final String? currencyCode;
  final bool? showActiveStatus, showInTravelBuddy, pushNotificationsEnabled;
  final bool settingsIncluded;
  bool get hasSettings =>
      settingsIncluded &&
      {'en', 'ar'}.contains(locale) &&
      (currencyCode == null || RegExp(r'^[A-Z]{3}$').hasMatch(currencyCode!)) &&
      showActiveStatus != null &&
      showInTravelBuddy != null &&
      pushNotificationsEnabled != null;
  final String? emailVerifiedAt;
  final String? termsAcceptedAt;
  final String? profileCompletedAt;
  final bool? profileCompleted;
  final String? createdAt;
  final String? updatedAt;
  final String? avatarUrl;
  final String? bio;
  final String? countryCode;
  final String? currentLocation;
  final bool locationIncluded;
  final String? nationality;
  final String? nationalityCode;
  final String? gender;
  final List<ProfileReference> languageSelections;
  final List<ProfileReference> interestSelections;
  final List<ProfileReference> travelStyleSelections;
  final int? postsCount;
  final int? followersCount;
  final int? followingCount;
  final bool? isMe;
  final bool? isFollowing;
  final bool? followsYou;
  final bool? isBlocked;

  // Use only supplied public identity; never turn an email into a display name.
  String get displayName =>
      name?.trim().isNotEmpty == true ? name! : username ?? '';
  List<String> get languages =>
      languageSelections.map((item) => item.name).toList();
  List<String> get interests =>
      interestSelections.map((item) => item.name).toList();
  List<String> get travelStyles =>
      travelStyleSelections.map((item) => item.name).toList();

  /// Settings confirmations must not replace a newer profile edit or counts
  /// with unrelated fields from an older full-resource settings response.
  ProfileModel withSettings(ProfileModel? source) {
    if (source == null || source.id != id) return this;
    if (!source.hasSettings) {
      return source.locationIncluded
          ? withLocation(source.currentLocation)
          : this;
    }
    return ProfileModel(
      id: id,
      name: name,
      username: username,
      email: email,
      locale: source.locale,
      currencyCode: source.currencyCode,
      showActiveStatus: source.showActiveStatus,
      showInTravelBuddy: source.showInTravelBuddy,
      pushNotificationsEnabled: source.pushNotificationsEnabled,
      settingsIncluded: true,
      emailVerifiedAt: emailVerifiedAt,
      termsAcceptedAt: termsAcceptedAt,
      profileCompletedAt: profileCompletedAt,
      profileCompleted: profileCompleted,
      createdAt: createdAt,
      updatedAt: updatedAt,
      avatarUrl: avatarUrl,
      bio: bio,
      countryCode: countryCode,
      currentLocation: source.locationIncluded
          ? source.currentLocation
          : currentLocation,
      locationIncluded: locationIncluded || source.locationIncluded,
      nationality: nationality,
      nationalityCode: nationalityCode,
      gender: gender,
      languageSelections: languageSelections,
      interestSelections: interestSelections,
      travelStyleSelections: travelStyleSelections,
      postsCount: postsCount,
      followersCount: followersCount,
      followingCount: followingCount,
      isMe: isMe,
      isFollowing: isFollowing,
      followsYou: followsYou,
      isBlocked: isBlocked,
    );
  }

  ProfileModel withLocation(String? value) {
    return ProfileModel(
      id: id,
      name: name,
      username: username,
      email: email,
      locale: locale,
      currencyCode: currencyCode,
      showActiveStatus: showActiveStatus,
      showInTravelBuddy: showInTravelBuddy,
      pushNotificationsEnabled: pushNotificationsEnabled,
      settingsIncluded: settingsIncluded,
      emailVerifiedAt: emailVerifiedAt,
      termsAcceptedAt: termsAcceptedAt,
      profileCompletedAt: profileCompletedAt,
      profileCompleted: profileCompleted,
      createdAt: createdAt,
      updatedAt: updatedAt,
      avatarUrl: avatarUrl,
      bio: bio,
      countryCode: countryCode,
      currentLocation: value,
      locationIncluded: true,
      nationality: nationality,
      nationalityCode: nationalityCode,
      gender: gender,
      languageSelections: languageSelections,
      interestSelections: interestSelections,
      travelStyleSelections: travelStyleSelections,
      postsCount: postsCount,
      followersCount: followersCount,
      followingCount: followingCount,
      isMe: isMe,
      isFollowing: isFollowing,
      followsYou: followsYou,
      isBlocked: isBlocked,
    );
  }

  static ApiError _invalid() => ApiError(
    message: 'Unable to read the profile response. Please try again.',
  );

  /// Parses the resource object, not an envelope. An empty array is not a profile.
  factory ProfileModel.fromJson(Map<String, dynamic> data) {
    final id = data['id'];
    if (id is! int || id < 1) throw _invalid();
    return ProfileModel(
      id: id.toString(),
      name: _string(
        data.containsKey('full_name') ? data['full_name'] : data['name'],
      ),
      username: _string(data['username']),
      email: _string(data['email']),
      locale: _string(data['locale']),
      currencyCode: _string(data['currency_code']),
      showActiveStatus: _flag(data['show_active_status']),
      showInTravelBuddy: _flag(data['show_in_travel_buddy']),
      pushNotificationsEnabled: _flag(data['push_notifications_enabled']),
      settingsIncluded: data.keys.toSet().containsAll(const {
        'locale',
        'currency_code',
        'show_active_status',
        'show_in_travel_buddy',
        'push_notifications_enabled',
      }),
      emailVerifiedAt: _string(data['email_verified_at']),
      termsAcceptedAt: _string(data['terms_accepted_at']),
      profileCompletedAt: _string(data['profile_completed_at']),
      profileCompleted: _flag(data['profile_completed']),
      createdAt: _string(data['created_at']),
      updatedAt: _string(data['updated_at']),
      avatarUrl: _string(data['avatar_url']),
      bio: _string(data['bio']),
      countryCode: _string(data['country_code']),
      currentLocation: _string(data['current_location']),
      locationIncluded: data.containsKey('current_location'),
      nationality: _string(data['nationality']),
      nationalityCode: _string(data['nationality_code']),
      gender: _string(data['gender']),
      // languages_spoken is confirmed for full profiles; languages is the
      // existing UserResource spelling. Never derive slugs from display labels.
      languageSelections: _references(
        data.containsKey('languages_spoken')
            ? data['languages_spoken']
            : data['languages'],
      ),
      interestSelections: _references(data['interests']),
      travelStyleSelections: _references(data['travel_styles']),
      postsCount: _count(data['posts_count']),
      followersCount: _count(data['followers_count']),
      followingCount: _count(data['following_count']),
      isMe: _flag(data['is_me']),
      isFollowing: _flag(data['is_following']),
      followsYou: _flag(data['follows_you']),
      isBlocked: _flag(data['is_blocked']),
    );
  }

  static String? _string(dynamic value) {
    if (value == null || value is String) return value as String?;
    throw _invalid();
  }

  static int? _count(dynamic value) {
    if (value == null) return null;
    if (value is int && value >= 0) return value;
    throw _invalid();
  }

  static bool? _flag(dynamic value) {
    if (value == null) return null;
    if (value == true || value == 1 || value == '1' || value == 'true') {
      return true;
    }
    if (value == false || value == 0 || value == '0' || value == 'false') {
      return false;
    }
    throw _invalid();
  }

  static List<ProfileReference> _references(dynamic value) {
    if (value == null) return const [];
    if (value is! List) throw _invalid();
    return List.unmodifiable(
      value.map((item) {
        if (item is! Map ||
            item['slug'] is! String ||
            item['name'] is! String ||
            (item['slug'] as String).trim().isEmpty ||
            (item['name'] as String).trim().isEmpty) {
          throw _invalid();
        }
        return ProfileReference(
          slug: item['slug'] as String,
          name: item['name'] as String,
        );
      }),
    );
  }
}
