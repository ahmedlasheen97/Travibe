import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';

class Mutation {
  Mutation(this.id, this.following);
  final String id;
  final bool following;
  final result = Completer<PublicUserModel>();
}

class FakeFollowRepo extends FollowRepo {
  final calls = <Mutation>[];
  final checks = <String>[];
  final statusResult = Completer<FollowStatus>();
  @override
  Future<PublicUserModel> setFollowing(String id, bool following) {
    final call = Mutation(id, following);
    calls.add(call);
    return call.result.future;
  }

  @override
  Future<FollowStatus> status(String id) {
    checks.add(id);
    return statusResult.future;
  }
}

PublicUserModel user(String id, bool following) => PublicUserModel.fromJson({
  'id': int.parse(id),
  'is_following': following.toString(),
  'followers_count': 12,
});
void main() {
  late FakeFollowRepo repo;
  late FollowCubit cubit;
  setUp(() {
    repo = FakeFollowRepo();
    cubit = FollowCubit(repo: repo);
  });
  tearDown(() => cubit.close());

  test(
    'confirmed response is shared, includes counts and increments revision',
    () async {
      final request = cubit.toggle('7', currentlyFollowing: false);
      expect(cubit.state.following['7'], isNull);
      expect(cubit.state.pending, contains('7'));
      repo.calls.single.result.complete(user('7', true));
      await request;
      expect(cubit.state.following['7'], isTrue);
      expect(cubit.state.users['7']!.followersCount, 12);
      expect(cubit.state.pending, isEmpty);
      expect(cubit.state.revision, 1);
      final unfollow = cubit.toggle(
        '7',
        currentlyFollowing: false,
      ); // stale other screen
      expect(repo.calls.last.following, isFalse);
      repo.calls.last.result.complete(user('7', false));
      await unfollow;
      expect(cubit.state.following['7'], isFalse);
      expect(cubit.state.revision, 2);
    },
  );
  test('duplicate mutations for a user are suppressed', () async {
    final request = cubit.toggle('7', currentlyFollowing: false);
    await cubit.toggle('7', currentlyFollowing: false);
    await cubit.checkStatus('7');
    expect(repo.calls, hasLength(1));
    expect(repo.checks, isEmpty);
    repo.calls.single.result.complete(user('7', true));
    await request;
  });
  test(
    'different users can mutate concurrently without losing shared state',
    () async {
      final a = cubit.toggle('7', currentlyFollowing: false);
      final b = cubit.toggle('8', currentlyFollowing: false);
      repo.calls[1].result.complete(user('8', true));
      await b;
      expect(cubit.state.pending, {'7'});
      repo.calls[0].result.complete(user('7', true));
      await a;
      expect(cubit.state.following, {'7': true, '8': true});
      expect(cubit.state.revision, 2);
    },
  );
  test(
    'failure keeps confirmed state and maps backend error, keeping status',
    () async {
      final unrelated = ApiError(message: 'Server busy', statusCode: 503);
      final first = cubit.toggle('7', currentlyFollowing: false);
      repo.calls.single.result.completeError(unrelated);
      expect(await first, same(unrelated));
      final error = ApiError(message: 'Blocked', statusCode: 422);
      final request = cubit.toggle('7', currentlyFollowing: false);
      repo.calls.last.result.completeError(error);
      final mapped = await request;
      expect(mapped?.message, "You can't follow this account.");
      expect(mapped?.statusCode, 422);
      expect(cubit.state.following, isEmpty);
      expect(cubit.state.pending, isEmpty);
      expect(cubit.state.revision, 0);
    },
  );
  test(
    '409 reconciles status without retrying or claiming mutation success',
    () async {
      final error = ApiError(message: 'Already following', statusCode: 409);
      final request = cubit.toggle('7', currentlyFollowing: false);
      repo.calls.single.result.completeError(error);
      await Future<void>.delayed(Duration.zero);
      expect(repo.checks, ['7']);
      repo.statusResult.complete(
        const FollowStatus(userId: '7', isFollowing: true),
      );
      final mapped = await request;
      expect(mapped?.message, 'You already follow or requested this account.');
      expect(mapped?.statusCode, error.statusCode);
      expect(cubit.state.following['7'], isTrue);
      expect(cubit.state.revision, 0);
      expect(repo.calls, hasLength(1));
    },
  );
  test('explicit status check shares result and prevents duplicates', () async {
    final request = cubit.checkStatus('7');
    await cubit.checkStatus('7');
    expect(repo.checks, ['7']);
    repo.statusResult.complete(
      const FollowStatus(userId: '7', isFollowing: true),
    );
    await request;
    expect(cubit.state.following['7'], isTrue);
  });
  test('late response after disposal does not emit', () async {
    final request = cubit.toggle('7', currentlyFollowing: false);
    await cubit.close();
    repo.calls.single.result.complete(user('7', true));
    await request;
    expect(cubit.state.revision, 0);
  });

  group('seed', () {
    test('fills unknown flags without a revision bump', () {
      cubit.seed('7', following: true, followsYou: true);
      expect(cubit.state.following['7'], isTrue);
      expect(cubit.state.followsYou['7'], isTrue);
      expect(cubit.state.revision, 0);
    });

    test('never overrides a confirmed mutation', () async {
      final request = cubit.toggle('7', currentlyFollowing: false);
      repo.calls.single.result.complete(user('7', true));
      await request;
      cubit.seed('7', following: false);
      expect(cubit.state.following['7'], isTrue);
      expect(cubit.state.revision, 1);
    });

    test(
      'is ignored while a mutation is pending and for null values',
      () async {
        final request = cubit.toggle('7', currentlyFollowing: false);
        cubit.seed('7', following: false, followsYou: true);
        expect(cubit.state.following['7'], isNull);
        expect(cubit.state.followsYou['7'], isNull);
        repo.calls.single.result.complete(user('7', true));
        await request;
        cubit.seed('8');
        expect(cubit.state.following.containsKey('8'), isFalse);
      },
    );
  });
}
