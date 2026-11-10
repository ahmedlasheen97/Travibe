import 'dart:async';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/search/data/users_page_model.dart';
import 'package:travibe/features/shares/data/send_post_repo.dart';

PublicUserModel person(String id, {bool blocked = false}) =>
    PublicUserModel.fromJson({
      'id': id,
      'name': 'Traveller $id',
      'is_blocked': blocked,
    });
UsersPageModel peoplePage(
  List<PublicUserModel> users, {
  int page = 1,
  int last = 1,
}) => UsersPageModel(
  users: users,
  currentPage: page,
  lastPage: last,
  total: users.length,
);

class PeopleRead {
  PeopleRead(this.query, this.page);
  final String query;
  final int page;
  final result = Completer<UsersPageModel>();
}

class SendPeopleRepo extends SendPostRepo {
  final calls = <PeopleRead>[];
  bool hold = false;
  ApiError? error;
  UsersPageModel result = peoplePage([person('2'), person('3')]);
  @override
  Future<UsersPageModel> users(String query, {int page = 1}) async {
    final read = PeopleRead(query, page);
    calls.add(read);
    if (hold) return read.result.future;
    if (error != null) throw error!;
    return result;
  }
}
