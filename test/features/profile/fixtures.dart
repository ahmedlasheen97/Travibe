import '../../helpers/cursor_fixtures.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/features/home/data/posts_page_model.dart';
import 'dart:async';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'package:travibe/features/profile/data/profile_repo.dart';

// Synthetic fixtures based on the confirmed task and existing resource shapes;
// these are not captured full-profile API responses.
Map<String, dynamic> profileJson({int id = 7, String name = 'Mona Hassan'}) => {
  'id': id,
  'name': name,
  'username': 'mona',
  'email': 'mona@example.invalid',
  'avatar_url': null,
  'bio': 'Exploring Egypt',
  'country_code': 'EG',
  'nationality': 'Egyptian',
  'posts_count': 5,
  'followers_count': 12,
  'following_count': 4,
  'languages_spoken': [
    {'slug': 'arabic', 'name': 'العربية'},
  ],
  'interests': [
    {'slug': 'photography', 'name': 'Photography'},
  ],
  'travel_styles': [
    {'slug': 'solo', 'name': 'Solo travel'},
  ],
};
ProfileModel profile({int id = 7, String name = 'Mona Hassan'}) =>
    ProfileModel.fromJson(profileJson(id: id, name: name));

class ProfileRead {
  ProfileRead(this.userId);
  final int? userId;
  final result = Completer<ProfileModel?>();
}

class MemoryProfileRepo extends ProfileRepo {
  final reads = <ProfileRead>[];
  ProfileModel? result = profile();
  Object? error;
  bool hold = false;
  Future<ProfileModel?> _read(int? id) async {
    final read = ProfileRead(id);
    reads.add(read);
    if (hold) return read.result.future;
    if (error != null) throw error!;
    return result;
  }

  @override
  Future<ProfileModel> getMyProfile() async => (await _read(null))!;
  @override
  Future<ProfileModel?> getPublicProfile(int userId) => _read(userId);
}

class EmptyProfilePostsRepo extends PostsRepo {
  @override
  Future<PostsPageModel> getUserPosts({
    required int userId,
    String? cursor,
    int perPage = 15,
  }) async => PostsPageModel(
    pagination: fixtureMeta(current: 1, last: 1),
    posts: [],
    currentPage: 1,
    lastPage: 1,
    total: 0,
  );
}
