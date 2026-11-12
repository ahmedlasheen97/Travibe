import '../../helpers/cursor_fixtures.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'dart:async';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';
import 'package:travibe/features/home/data/home_account_repo.dart';
import 'package:travibe/features/home/data/posts_page_model.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/features/search/data/users_page_model.dart';

class AccountRepo extends HomeAccountRepo {
  int? followingCount = 0;
  int calls = 0;
  ApiError? error;
  Completer<HomeAccount>? gate;
  @override
  Future<HomeAccount> getAccount() async {
    calls++;
    if (gate != null) return gate!.future;
    if (error != null) throw error!;
    return HomeAccount(id: '1', name: 'Viewer', followingCount: followingCount);
  }
}

PublicUserModel suggested(
  String id, {
  String name = 'Traveller',
  String? username = 'traveller',
}) => PublicUserModel.fromJson({
  'id': int.parse(id),
  'name': name,
  'username': username,
  'avatar_url': null,
});

class PeopleRepo extends FollowRepo {
  PeopleRepo(this.account);
  final AccountRepo account;
  List<PublicUserModel> suggestions = [suggested('2')];
  final Set<String> following = {};
  int mutations = 0;
  int listCalls = 0;
  Completer<PublicUserModel>? mutationGate;
  ApiError? listError;
  @override
  Future<PublicUserModel> setFollowing(String id, bool value) async {
    mutations++;
    if (mutationGate != null) return mutationGate!.future;
    if (value) {
      following.add(id);
    } else {
      following.remove(id);
    }
    account.followingCount = following.length;
    return suggested(id).copyWith(isFollowing: value);
  }

  @override
  Future<UsersPageModel> users({
    required FollowListType type,
    String? userId,
    int page = 1,
    int perPage = 15,
  }) async {
    listCalls++;
    if (listError != null) throw listError!;
    return UsersPageModel(
      users: suggestions,
      currentPage: page,
      lastPage: 1,
      total: suggestions.length,
    );
  }
}

class EmptyPostsRepo extends PostsRepo {
  final requests = <({FeedType feed, String? cursor})>[];
  ApiError? error;
  Completer<PostsPageModel>? followingGate;
  List<PostModel> explorePosts = [];
  @override
  Future<PostsPageModel> getPosts({
    FeedType feed = FeedType.explore,
    String? cursor,
    int perPage = 15,
  }) async {
    requests.add((feed: feed, cursor: cursor));
    if (feed == FeedType.following && followingGate != null) {
      return followingGate!.future;
    }
    if (error != null) throw error!;
    return PostsPageModel(
      pagination: fixtureMeta(current: 1, last: 1),
      posts: feed == FeedType.explore ? explorePosts : [],
      currentPage: 1,
      lastPage: 1,
      total: 0,
    );
  }
}
