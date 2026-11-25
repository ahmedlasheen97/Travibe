import 'dart:async';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/home/data/posts_page_model.dart';
import 'package:travibe/features/search/data/recent_search.dart';
import 'package:travibe/features/search/data/search_repo.dart';
import 'package:travibe/features/search/data/users_page_model.dart';
import '../home/home_experience_fixtures.dart';

class SearchFixture extends SearchRepo {
  final List<String> queries = [];

  /// Recents per account id; [userId] is the signed-in account.
  final Map<String, List<RecentSearch>> store = {};
  String userId = '1';
  List<RecentSearch> get recents => store[userId] ?? const [];
  set recents(List<RecentSearch> values) => store[userId] = values;
  List<String> get recentTexts => [for (final r in recents) r.text];
  Future<UsersPageModel> Function(String, int)? handler;

  /// Post searches, recorded as "posts:query:page".
  final List<String> postQueries = [];
  Future<PostsPageModel> Function(String, int)? postsHandler;
  @override
  Future<PostsPageModel> searchPosts(
    String query, {
    int page = 1,
    int perPage = 15,
  }) async {
    postQueries.add('posts:$query:$page');
    return postsHandler != null
        ? postsHandler!(query, page)
        : postsPage(const [], page: page);
  }

  @override
  Future<String> getCurrentUserId() async => userId;
  @override
  List<RecentSearch> getRecentSearches(String userId) =>
      store[userId] ?? const [];
  @override
  Future<void> saveRecentSearches(
    String userId,
    List<RecentSearch> values,
  ) async => store[userId] = values;
  @override
  Future<UsersPageModel> searchUsers(String query, {int page = 1}) async {
    queries.add('$query:$page');
    return handler != null ? handler!(query, page) : usersPage();
  }
}

UsersPageModel usersPage({bool empty = false, int page = 1, int last = 1}) =>
    UsersPageModel(
      users: empty ? [] : [suggested('2', name: 'Sarah Travels')],
      currentPage: page,
      lastPage: last,
      total: empty ? 0 : last,
    );

Future<void> settleRequests() => Future<void>.delayed(Duration.zero);

Map<String, dynamic> searchPostJson(int id, {int authorId = 9}) => {
  'id': id,
  'user_id': authorId,
  'content': 'Bali sunset $id',
  'user': {
    'id': authorId,
    'name': 'Traveler $authorId',
    'username': 't$authorId',
  },
  'media': <dynamic>[],
  'visibility': 'public',
  'is_saved': false,
  'is_liked': false,
  'likes_count': 2,
  'comments_count': 1,
};

PostsPageModel postsPage(List<int> ids, {int page = 1, int last = 1}) =>
    PostsPageModel(
      posts: [for (final id in ids) PostModel.fromJson(searchPostJson(id))],
      currentPage: page,
      lastPage: last,
      total: ids.length,
    );
