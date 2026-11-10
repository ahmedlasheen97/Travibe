import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/follow/cubit/follow_users_cubit.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';
import 'package:travibe/features/search/data/users_page_model.dart';

class UserPageCall {
  UserPageCall(this.type, this.userId, this.page);
  final FollowListType type;
  final String? userId;
  final int page;
  final result = Completer<UsersPageModel>();
}

class FakeListRepo extends FollowRepo {
  final calls = <UserPageCall>[];
  @override
  Future<UsersPageModel> users({
    required FollowListType type,
    String? userId,
    int page = 1,
    int perPage = 15,
  }) {
    final call = UserPageCall(type, userId, page);
    calls.add(call);
    return call.result.future;
  }
}

UsersPageModel page(int current, List<int> ids, {int last = 2}) =>
    UsersPageModel(
      users: ids.map((id) => PublicUserModel.fromJson({'id': id})).toList(),
      currentPage: current,
      lastPage: last,
      total: 30,
    );
void main() {
  late FakeListRepo repo;
  late FollowUsersCubit cubit;
  setUp(() {
    repo = FakeListRepo();
    cubit = FollowUsersCubit(
      repo: repo,
      type: FollowListType.followers,
      userId: '7',
    );
  });
  tearDown(() => cubit.close());
  Future<void> load() async {
    final request = cubit.load();
    repo.calls.last.result.complete(page(1, [1]));
    await request;
  }

  test('loads list identity and coalesces duplicate initial loads', () async {
    final request = cubit.load();
    final duplicate = cubit.load();
    expect(cubit.state.status, FollowUsersStatus.loading);
    expect(repo.calls, hasLength(1));
    expect(repo.calls.single.type, FollowListType.followers);
    expect(repo.calls.single.userId, '7');
    repo.calls.single.result.complete(page(1, [1]));
    await Future.wait([request, duplicate]);
    expect(cubit.state.users.single.id, '1');
  });
  test('empty success and last page prevent pagination', () async {
    final request = cubit.load();
    repo.calls.single.result.complete(page(1, [], last: 1));
    await request;
    expect(cubit.state.status, FollowUsersStatus.loaded);
    expect(cubit.state.users, isEmpty);
    await cubit.more();
    expect(repo.calls, hasLength(1));
  });
  test(
    'pagination deduplicates, locks duplicate calls and stops at last page',
    () async {
      await load();
      final request = cubit.more();
      await cubit.more();
      expect(repo.calls, hasLength(2));
      expect(repo.calls.last.page, 2);
      repo.calls.last.result.complete(page(2, [1, 2]));
      await request;
      expect(cubit.state.users.map((u) => u.id), ['1', '2']);
      await cubit.more();
      expect(repo.calls, hasLength(2));
    },
  );
  test(
    'pagination failure retains users and retries the same page explicitly',
    () async {
      await load();
      final request = cubit.more();
      final error = ApiError(message: 'Try later', statusCode: 429);
      repo.calls.last.result.completeError(error);
      await request;
      expect(cubit.state.paginationError, same(error));
      expect(cubit.state.users.single.id, '1');
      await cubit.more();
      expect(repo.calls, hasLength(2));
      final retry = cubit.more(retry: true);
      expect(repo.calls.last.page, 2);
      repo.calls.last.result.complete(page(2, [2]));
      await retry;
      expect(cubit.state.paginationError, isNull);
    },
  );
  test('refresh supersedes pagination and ignores late results', () async {
    await load();
    final old = cubit.more();
    final oldCall = repo.calls.last;
    final refresh = cubit.load();
    expect(cubit.state.refreshing, isTrue);
    repo.calls.last.result.complete(page(1, [3]));
    await refresh;
    oldCall.result.complete(page(2, [99]));
    await old;
    expect(cubit.state.users.single.id, '3');
  });
  test('initial error preserves status and can retry', () async {
    final request = cubit.load();
    final error = ApiError(message: 'Unauthenticated', statusCode: 401);
    repo.calls.single.result.completeError(error);
    await request;
    expect(cubit.state.status, FollowUsersStatus.failure);
    expect(cubit.state.error, same(error));
    await load();
    expect(cubit.state.status, FollowUsersStatus.loaded);
  });
  test('refresh failure preserves existing users and pagination', () async {
    await load();
    final request = cubit.load();
    final error = ApiError(message: 'Unavailable', statusCode: 503);
    repo.calls.last.result.completeError(error);
    await request;
    expect(cubit.state.users.single.id, '1');
    expect(cubit.state.error, same(error));
    expect(cubit.state.refreshing, isFalse);
    final more = cubit.more();
    expect(repo.calls.last.page, 2);
    repo.calls.last.result.complete(page(2, [2]));
    await more;
  });
  test('disposal ignores a late response', () async {
    final request = cubit.load();
    await cubit.close();
    repo.calls.single.result.complete(page(1, [1]));
    await request;
    expect(cubit.state.status, FollowUsersStatus.loading);
  });
}
