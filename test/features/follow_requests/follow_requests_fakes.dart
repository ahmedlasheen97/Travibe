import 'dart:async';

import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/follow_requests/data/follow_requests_repo.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/search/data/users_page_model.dart';

Map<String, dynamic> requesterJson(int id, {String? name, String? username}) =>
    {
      'id': id,
      'name': name ?? 'User $id',
      'username': username ?? 'user$id',
      'is_private': false,
      'is_following': false,
      'follows_you': false,
      'followers_count': 1,
      'following_count': 2,
    };

UsersPageModel requestsPage(
  List<int> ids, {
  int page = 1,
  int lastPage = 1,
  int? total,
}) => UsersPageModel.fromJson({
  'data': [for (final id in ids) requesterJson(id)],
  'meta': {
    'current_page': page,
    'last_page': lastPage,
    'total': total ?? ids.length,
  },
});

/// Scriptable [FollowRequestsRepo]: pages by number, accept/decline results.
class FakeFollowRequestsRepo extends FollowRequestsRepo {
  FakeFollowRequestsRepo({Map<int, UsersPageModel>? pages})
    : pages = pages ?? {1: requestsPage(const [])};
  final Map<int, UsersPageModel> pages;
  final listCalls = <(int, int)>[];
  final accepted = <String>[];
  final declined = <String>[];
  Completer<void>? gate;
  ApiError? acceptError, declineError;

  @override
  Future<UsersPageModel> list({int page = 1, int perPage = 15}) async {
    listCalls.add((page, perPage));
    return pages[page] ?? requestsPage(const [], page: page, lastPage: page);
  }

  @override
  Future<PublicUserModel> accept(String userId) async {
    accepted.add(userId);
    await gate?.future;
    if (acceptError != null) throw acceptError!;
    return PublicUserModel.fromJson({
      ...requesterJson(int.parse(userId)),
      'follows_you': true,
    });
  }

  @override
  Future<void> decline(String userId) async {
    declined.add(userId);
    await gate?.future;
    if (declineError != null) throw declineError!;
  }
}

/// Records optimistic follower-count deltas.
class CountingCurrentUser extends CurrentUserCubit {
  final deltas = <int>[];
  @override
  void adjustFollowersCount(int delta) => deltas.add(delta);
}
