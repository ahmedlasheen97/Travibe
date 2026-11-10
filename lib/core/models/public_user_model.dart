import 'package:travibe/core/utils/json_parsers.dart';

class PublicUserModel {
  final String id;
  final String name;
  final String? username;
  final String? countryCode;
  final String? avatarUrl;
  final bool isFollowing;
  final bool followsYou;
  final bool isBlocked;
  final int followersCount;
  final int followingCount;

  const PublicUserModel({
    required this.id,
    required this.name,
    this.username,
    this.countryCode,
    this.avatarUrl,
    required this.isFollowing,
    this.followsYou = false,
    required this.isBlocked,
    required this.followersCount,
    required this.followingCount,
  });

  /// "@username", or empty if the user has none yet.
  String get handle =>
      (username != null && username!.isNotEmpty) ? '@$username' : '';

  factory PublicUserModel.fromJson(Map<String, dynamic> json) {
    return PublicUserModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      username: json['username']?.toString(),
      countryCode: json['country_code']?.toString(),
      avatarUrl: json['avatar_url']?.toString(),
      isFollowing: parseBool(json['is_following']),
      followsYou: parseBool(json['follows_you']),
      isBlocked: parseBool(json['is_blocked']),
      followersCount: parseInt(json['followers_count']),
      followingCount: parseInt(json['following_count']),
    );
  }

  PublicUserModel copyWith({
    bool? isFollowing,
    bool? followsYou,
    bool? isBlocked,
    int? followersCount,
  }) {
    return PublicUserModel(
      id: id,
      name: name,
      username: username,
      countryCode: countryCode,
      avatarUrl: avatarUrl,
      isFollowing: isFollowing ?? this.isFollowing,
      followsYou: followsYou ?? this.followsYou,
      isBlocked: isBlocked ?? this.isBlocked,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount,
    );
  }
}
