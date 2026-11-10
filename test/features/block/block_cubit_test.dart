import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/block/data/block_repo.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';
import 'package:travibe/features/search/data/users_page_model.dart';

class Mutation {
  Mutation(this.id, this.blocked);
  final String id;
  final bool blocked;
  final result = Completer<PublicUserModel>();
}

class Repo extends BlockRepo {
  final calls = <Mutation>[];
  final pages = <Completer<UsersPageModel>>[];
  final checks = <Completer<BlockStatus>>[];
  @override
  Future<PublicUserModel> setBlocked(String id, bool blocked) {
    final call = Mutation(id, blocked);
    calls.add(call);
    return call.result.future;
  }

  @override
  Future<BlockStatus> status(String id) {
    final check = Completer<BlockStatus>();
    checks.add(check);
    return check.future;
  }

  @override
  Future<UsersPageModel> users({int page = 1, int perPage = 15}) {
    final result = Completer<UsersPageModel>();
    pages.add(result);
    return result.future;
  }
}

class Follows extends FollowRepo {
  final calls = <Completer<PublicUserModel>>[];
  @override
  Future<PublicUserModel> setFollowing(String id, bool following) {
    final result = Completer<PublicUserModel>();
    calls.add(result);
    return result.future;
  }
}

PublicUserModel user(String id, bool blocked, {bool following = true}) =>
    PublicUserModel.fromJson({
      'id': int.parse(id),
      'is_blocked': blocked.toString(),
      'is_following': following.toString(),
      'followers_count': 12,
    });
UsersPageModel page(List<PublicUserModel> users) =>
    UsersPageModel(users: users, currentPage: 1, lastPage: 2, total: 30);
void main() {
  late Repo repo;
  late Follows follows;
  late FollowCubit follow;
  late BlockCubit block;
  setUp(() {
    repo = Repo();
    follows = Follows();
    follow = FollowCubit(repo: follows);
    block = BlockCubit(repo: repo, follow: follow);
  });
  tearDown(() async {
    await block.close();
    await follow.close();
  });
  Future<void> change(bool value, {String id = '7'}) async {
    final request = block.setBlocked(id, value);
    repo.calls.last.result.complete(user(id, value));
    expect(await request, isNull);
  }

  test(
    'block is confirmed before updating state and preserves the follow relationship',
    () async {
      final request = block.setBlocked('7', true);
      expect(block.state.blocked, isEmpty);
      expect(follow.canInteract('7'), isFalse);
      repo.calls.single.result.complete(user('7', true));
      await request;
      expect(block.state.isBlocked('7'), isTrue);
      expect(block.state.pending, isEmpty);
      expect(follow.state.following['7'], isTrue);
      expect(follow.state.users['7']!.followersCount, 12);
      expect(
        await follow.toggle('7', currentlyFollowing: true),
        isA<ApiError>(),
      );
      expect(follows.calls, isEmpty);
    },
  );
  test(
    'unblock restores controls without unfollowing or creating a new follow',
    () async {
      await change(true);
      final request = block.setBlocked('7', false);
      expect(block.state.isBlocked('7'), isTrue);
      repo.calls.last.result.complete(user('7', false));
      await request;
      expect(block.state.isBlocked('7'), isFalse);
      expect(follow.canInteract('7'), isTrue);
      expect(follow.state.following['7'], isTrue);
      expect(follows.calls, isEmpty);
      expect(block.state.unblockRevision, 1);
    },
  );
  test(
    'duplicate/opposite mutations and status checks are locked per user',
    () async {
      for (final value in [true, false]) {
        final count = repo.calls.length;
        final request = block.setBlocked('7', value);
        await block.setBlocked('7', value);
        await block.setBlocked('7', !value);
        await block.checkStatus('7');
        expect(repo.calls, hasLength(count + 1));
        expect(repo.checks, isEmpty);
        repo.calls.last.result.complete(user('7', value));
        await request;
      }
    },
  );
  test('different users mutate concurrently without losing state', () async {
    final a = block.setBlocked('7', true);
    final b = block.setBlocked('8', true);
    repo.calls[1].result.complete(user('8', true));
    await b;
    expect(block.state.pending, {'7'});
    repo.calls[0].result.complete(user('7', true));
    await a;
    expect(block.state.blockedIds, {'7', '8'});
  });
  test(
    'failure preserves backend error and does not change blocked/follow state',
    () async {
      final error = ApiError(message: 'Cannot block yourself', statusCode: 422);
      final request = block.setBlocked('7', true);
      repo.calls.last.result.completeError(error);
      expect(await request, same(error));
      expect(block.state.blocked, isEmpty);
      expect(follow.canInteract('7'), isTrue);
      expect(block.state.mutationRevision, 0);
    },
  );
  test('unblock failure leaves follow controls disabled', () async {
    await change(true);
    final request = block.setBlocked('7', false);
    final error = ApiError(message: 'Forbidden', statusCode: 403);
    repo.calls.last.result.completeError(error);
    expect(await request, same(error));
    expect(block.state.isBlocked('7'), isTrue);
    expect(follow.canInteract('7'), isFalse);
  });
  test('a pending follow prevents a racing block request', () async {
    final request = follow.toggle('7', currentlyFollowing: false);
    expect(await block.setBlocked('7', true), isA<ApiError>());
    expect(repo.calls, isEmpty);
    follows.calls.single.complete(user('7', false));
    await request;
  });
  test('status check updates own block without changing follows', () async {
    final request = block.checkStatus('7');
    repo.checks.single.complete(
      const BlockStatus(userId: '7', isBlocked: true),
    );
    await request;
    expect(block.state.isBlocked('7'), isTrue);
    expect(follow.canInteract('7'), isFalse);
    expect(follow.state.following, isEmpty);
  });
  test('late blocked list cannot reverse a confirmed unblock', () async {
    await change(true);
    final request = block.loadUsers(1);
    await change(false);
    repo.pages.last.complete(page([user('7', true)]));
    await request;
    expect(block.state.isBlocked('7'), isFalse);
    expect(follow.canInteract('7'), isTrue);
  });
  test('superseded pagination cannot republish old block state', () async {
    final stale = block.loadUsers(2);
    final old = repo.pages.last;
    final refresh = block.loadUsers(1);
    repo.pages.last.complete(page([]));
    await refresh;
    old.complete(page([user('7', true)]));
    await stale;
    expect(block.state.blocked, isEmpty);
  });
  test('late list cannot overwrite a newer follow mutation', () async {
    final list = block.loadUsers(1);
    final request = follow.toggle('7', currentlyFollowing: false);
    follows.calls.single.complete(user('7', false, following: true));
    await request;
    repo.pages.last.complete(page([user('7', true, following: false)]));
    await list;
    expect(follow.state.following['7'], isTrue);
    expect(block.state.isBlocked('7'), isTrue);
  });
  test('disposed session ignores late success and releases locks', () async {
    final request = block.setBlocked('7', true);
    await block.close();
    repo.calls.last.result.complete(user('7', true));
    await request;
    expect(block.state.blocked, isEmpty);
    expect(follow.canInteract('7'), isTrue);
  });
}
