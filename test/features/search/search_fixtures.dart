import 'dart:async';
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
