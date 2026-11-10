import 'dart:async';
import 'package:travibe/features/search/data/search_repo.dart';
import 'package:travibe/features/search/data/users_page_model.dart';
import '../home/home_experience_fixtures.dart';

class SearchFixture extends SearchRepo {
  final List<String> queries = [];
  List<String> recents = [];
  Future<UsersPageModel> Function(String, int)? handler;
  @override
  Future<String> getCurrentUserId() async => '1';
  @override
  List<String> getRecentSearches() => recents;
  @override
  Future<void> saveRecentSearches(List<String> values) async =>
      recents = values;
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
