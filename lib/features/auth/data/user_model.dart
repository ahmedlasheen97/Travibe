class UserModel {
  final String id;
  final String name;
  final String email;
  final String? emailVerifiedAt;
  final String? createdAt;
  final String? updatedAt;
  final bool isFollowing;
  final int followersCount;
  final int followingCount;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.emailVerifiedAt,
    this.createdAt,
    this.updatedAt,
    required this.isFollowing,
    required this.followersCount,
    required this.followingCount,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      emailVerifiedAt: json['email_verified_at']?.toString(),
      createdAt: json['created_at']?.toString(),
      updatedAt: json['updated_at']?.toString(),

      // Handles "true", true, "1", 1
      isFollowing:
          json['is_following'] == true ||
          json['is_following'] == 'true' ||
          json['is_following'] == 1 ||
          json['is_following'] == '1',

      followersCount:
          int.tryParse(json['followers_count']?.toString() ?? '0') ?? 0,

      followingCount:
          int.tryParse(json['following_count']?.toString() ?? '0') ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'email_verified_at': emailVerifiedAt,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'is_following': isFollowing,
      'followers_count': followersCount,
      'following_count': followingCount,
    };
  }
}
