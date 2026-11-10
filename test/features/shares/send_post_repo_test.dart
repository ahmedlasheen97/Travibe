import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';
import 'package:travibe/features/search/data/search_repo.dart';
import 'package:travibe/features/search/data/users_page_model.dart';
import 'package:travibe/features/shares/data/send_post_repo.dart';
import 'send_post_fixtures.dart';

class Discovery extends FollowRepo {
  FollowListType? type;
  int? page;
  @override
  Future<UsersPageModel> users({
    required FollowListType type,
    String? userId,
    int page = 1,
    int perPage = 15,
  }) async {
    this.type = type;
    this.page = page;
    return peoplePage([person('2')], page: page, last: 2);
  }
}

class Search extends SearchRepo {
  String? query;
  int? page;
  @override
  Future<UsersPageModel> searchUsers(String query, {int page = 1}) async {
    this.query = query;
    this.page = page;
    return peoplePage([person('3')], page: page, last: 2);
  }
}

void main() {
  test(
    'blank query reuses discovery; nonblank reuses paginated user search',
    () async {
      final discovery = Discovery();
      final search = Search();
      final repo = SendPostRepo(discovery: discovery, search: search);
      expect((await repo.users(' ', page: 2)).users.single.id, '2');
      expect(discovery.type, FollowListType.suggested);
      expect(discovery.page, 2);
      expect(search.query, isNull);
      expect((await repo.users('alice', page: 2)).users.single.id, '3');
      expect(search.query, 'alice');
      expect(search.page, 2);
    },
  );
}
