import 'package:travibe/features/follow/data/follow_repo.dart';
import 'package:travibe/features/search/data/search_repo.dart';
import 'package:travibe/features/search/data/users_page_model.dart';

/// Reuses discovery and search without changing their state or recent searches.
class SendPostRepo {
  SendPostRepo({FollowRepo? discovery, SearchRepo? search})
    : _discovery = discovery ?? FollowRepo(),
      _search = search ?? SearchRepo();

  final FollowRepo _discovery;
  final SearchRepo _search;

  Future<UsersPageModel> users(String query, {int page = 1}) =>
      query.trim().isEmpty
      ? _discovery.users(type: FollowListType.suggested, page: page)
      : _search.searchUsers(query, page: page);
}
