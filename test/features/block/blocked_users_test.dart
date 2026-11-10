import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/block/data/block_repo.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_users_cubit.dart';
import 'package:travibe/features/search/data/users_page_model.dart';

class PageRequest {
  PageRequest(this.page);
  final int page;
  final result = Completer<UsersPageModel>();
}

class ListRepo extends BlockRepo {
  final requests = <PageRequest>[];
  @override
  Future<UsersPageModel> users({int page = 1, int perPage = 15}) {
    final request = PageRequest(page);
    requests.add(request);
    return request.result.future;
  }
}

UsersPageModel page(int current, List<int> ids, {int last = 2}) =>
    UsersPageModel(
      users: ids
          .map(
            (id) =>
                PublicUserModel.fromJson({'id': id, 'is_following': 'true'}),
          )
          .toList(),
      currentPage: current,
      lastPage: last,
      total: 30,
    );
void main() {
  late ListRepo repo;
  late FollowCubit follow;
  late BlockCubit block;
  late FollowUsersCubit list;
  setUp(() {
    repo = ListRepo();
    follow = FollowCubit();
    block = BlockCubit(repo: repo, follow: follow);
    list = FollowUsersCubit(loadPage: block.loadUsers);
  });
  tearDown(() async {
    await list.close();
    await block.close();
    await follow.close();
  });
  Future<void> load() async {
    final request = list.load();
    repo.requests.last.result.complete(page(1, [7]));
    await request;
  }

  test(
    'initial loading coalesces and hydrates shared block/follow state',
    () async {
      final request = list.load();
      final duplicate = list.load();
      expect(list.state.status, FollowUsersStatus.loading);
      expect(repo.requests, hasLength(1));
      repo.requests.last.result.complete(page(1, [7]));
      await Future.wait([request, duplicate]);
      expect(block.state.isBlocked('7'), isTrue);
      expect(follow.state.following['7'], isTrue);
      expect(follow.canInteract('7'), isFalse);
    },
  );
  test('empty success stops pagination', () async {
    final request = list.load();
    repo.requests.last.result.complete(page(1, [], last: 1));
    await request;
    expect(list.state.status, FollowUsersStatus.loaded);
    expect(list.state.users, isEmpty);
    await list.more();
    expect(repo.requests, hasLength(1));
  });
  test(
    'pagination locks duplicate calls, deduplicates and stops at last page',
    () async {
      await load();
      final request = list.more();
      await list.more();
      expect(repo.requests, hasLength(2));
      expect(repo.requests.last.page, 2);
      repo.requests.last.result.complete(page(2, [7, 8]));
      await request;
      expect(list.state.users.map((u) => u.id), ['7', '8']);
      await list.more();
      expect(repo.requests, hasLength(2));
    },
  );
  test(
    'pagination failure preserves rows/status and retries the same page',
    () async {
      await load();
      final request = list.more();
      final error = ApiError(message: 'Try later', statusCode: 429);
      repo.requests.last.result.completeError(error);
      await request;
      expect(list.state.users.single.id, '7');
      expect(list.state.paginationError, same(error));
      await list.more();
      expect(repo.requests, hasLength(2));
      final retry = list.more(retry: true);
      expect(repo.requests.last.page, 2);
      repo.requests.last.result.complete(page(2, [8]));
      await retry;
      expect(list.state.paginationError, isNull);
    },
  );
  test(
    'refresh invalidates stale pagination in both list and shared block state',
    () async {
      await load();
      final more = list.more();
      final stale = repo.requests.last;
      final refresh = list.load();
      repo.requests.last.result.complete(page(1, [9]));
      await refresh;
      stale.result.complete(page(2, [8]));
      await more;
      expect(list.state.users.single.id, '9');
      expect(block.state.blocked.containsKey('8'), isFalse);
    },
  );
  test(
    'initial and refresh failures retain backend errors and existing rows',
    () async {
      final error = ApiError(message: 'Unauthenticated', statusCode: 401);
      final request = list.load();
      repo.requests.last.result.completeError(error);
      await request;
      expect(list.state.status, FollowUsersStatus.failure);
      expect(list.state.error, same(error));
      await load();
      final refresh = list.load();
      repo.requests.last.result.completeError(error);
      await refresh;
      expect(list.state.status, FollowUsersStatus.loaded);
      expect(list.state.users.single.id, '7');
      expect(list.state.error, same(error));
      expect(list.state.refreshing, isFalse);
    },
  );
}
