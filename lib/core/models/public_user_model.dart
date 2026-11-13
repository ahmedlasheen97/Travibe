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
  final bool isPrivate;

  /// The viewer has a pending follow request to this user.
  final bool followRequested;
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
    this.isPrivate = false,
    this.followRequested = false,
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
      isPrivate: parseBool(json['is_private']),
      followRequested: parseBool(json['follow_requested']),
      followersCount: parseInt(json['followers_count']),
      followingCount: parseInt(json['following_count']),
    );
  }

  PublicUserModel copyWith({
    bool? isFollowing,
    bool? followsYou,
    bool? isBlocked,
    bool? followRequested,
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
      isPrivate: isPrivate,
      followRequested: followRequested ?? this.followRequested,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount,
    );
  }
}
