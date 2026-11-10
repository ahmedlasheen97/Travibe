import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/likes/cubit/likes_cubit.dart';
import 'package:travibe/features/likes/data/like_model.dart';
import 'fixtures.dart';

void main() {
  late PendingLikesRepo repo;
  late LikesCubit cubit;
  const target = LikeTarget.post(10);
  const initial = LikeValue(isLiked: false, count: 4);
  setUp(() {
    repo = PendingLikesRepo();
    cubit = LikesCubit(repo: repo);
  });
  tearDown(() => cubit.close());

  test(
    'optimistic like, duplicate protection and authoritative reconciliation',
    () async {
      final request = cubit.toggle(target, initial: initial);
      expect(cubit.value(target)!.isLiked, isTrue);
      expect(cubit.value(target)!.count, 5);
      expect(cubit.value(target)!.pending, isTrue);
      await cubit.toggle(target, initial: initial);
      expect(repo.writes, hasLength(1));
      expect(repo.writes.single.liked, isTrue);
      repo.writes.single.result.complete(
        const LikeValue(isLiked: true, count: 8),
      );
      expect(await request, isNull);
      expect(cubit.value(target)!.count, 8);
      expect(cubit.value(target)!.pending, isFalse);
    },
  );
  test(
    'optimistic unlike never goes below zero and accepts idempotent response',
    () async {
      final request = cubit.toggle(
        target,
        initial: const LikeValue(isLiked: true, count: 0),
      );
      expect(cubit.value(target)!.isLiked, isFalse);
      expect(cubit.value(target)!.count, 0);
      expect(repo.writes.single.liked, isFalse);
      repo.writes.single.result.complete(
        const LikeValue(isLiked: false, count: 0),
      );
      await request;
      expect(cubit.value(target)!.pending, isFalse);
    },
  );
  for (final status in [401, 403, 404, 422, null]) {
    test('failure $status rolls back heart/count and permits retry', () async {
      final error = ApiError(message: 'Like failed', statusCode: status);
      final request = cubit.toggle(target, initial: initial);
      repo.writes.single.result.completeError(error);
      expect(await request, same(error));
      expect(cubit.value(target)!.isLiked, isFalse);
      expect(cubit.value(target)!.count, 4);
      expect(cubit.value(target)!.pending, isFalse);
      final retry = cubit.toggle(target);
      repo.writes.last.result.complete(
        const LikeValue(isLiked: true, count: 5),
      );
      expect(await retry, isNull);
    });
  }
  test('older reads cannot overwrite pending or confirmed likes', () async {
    final oldRevision = cubit.revision;
    final request = cubit.toggle(target, initial: initial);
    cubit.accept({target: initial}, requestRevision: cubit.revision);
    expect(cubit.value(target)!.pending, isTrue);
    repo.writes.single.result.complete(
      const LikeValue(isLiked: true, count: 5),
    );
    await request;
    cubit.accept({target: initial}, requestRevision: oldRevision);
    expect(cubit.value(target)!.isLiked, isTrue);
    cubit.accept({
      target: const LikeValue(isLiked: true, count: 9),
    }, requestRevision: cubit.revision);
    expect(cubit.value(target)!.count, 9);
  });
  test('rollback also invalidates older reads', () async {
    final oldRevision = cubit.revision;
    final request = cubit.toggle(target, initial: initial);
    repo.writes.single.result.completeError(ApiError(message: 'Failed'));
    await request;
    cubit.accept({
      target: const LikeValue(isLiked: true, count: 20),
    }, requestRevision: oldRevision);
    expect(cubit.value(target)!.isLiked, isFalse);
    expect(cubit.value(target)!.count, 4);
  });
  test('unknown viewer state does not infer a like from a count', () async {
    final error = await cubit.toggle(target);
    expect(error, isNotNull);
    expect(repo.writes, isEmpty);
    expect(cubit.value(target), isNull);
  });
  test(
    'successful response without state reconciles with one resource read',
    () async {
      final source = StateLessLikesRepo();
      final shared = LikesCubit(repo: source);
      addTearDown(shared.close);
      final request = shared.toggle(target, initial: initial);
      await flushLikes();
      expect(source.reads, 1);
      expect(shared.value(target)!.count, 5);
      expect(shared.value(target)!.pending, isTrue);
      await shared.toggle(target);
      expect(source.writes, 1);
      source.read.complete(const LikeValue(isLiked: true, count: 12));
      expect(await request, isNull);
      expect(shared.value(target)!.count, 12);
      expect(shared.value(target)!.pending, isFalse);
    },
  );
  test(
    'failed reconciliation retains a confirmed write and clears pending',
    () async {
      final source = StateLessLikesRepo();
      final shared = LikesCubit(repo: source);
      addTearDown(shared.close);
      final request = shared.toggle(target, initial: initial);
      await flushLikes();
      source.read.completeError(
        ApiError(message: 'Network failed', statusCode: 503),
      );
      final error = await request;
      expect(error!.message, 'Like updated. Network failed');
      expect(error.statusCode, 503);
      expect(shared.value(target)!.isLiked, isTrue);
      expect(shared.value(target)!.count, 5);
      expect(shared.value(target)!.pending, isFalse);
    },
  );
  test('different posts and replies mutate independently', () async {
    const reply = LikeTarget.comment(10, 10);
    final postRequest = cubit.toggle(target, initial: initial);
    final replyRequest = cubit.toggle(reply, initial: initial);
    expect(repo.writes, hasLength(2));
    repo.writes[1].result.complete(const LikeValue(isLiked: true, count: 6));
    repo.writes[0].result.complete(const LikeValue(isLiked: true, count: 5));
    await Future.wait([postRequest, replyRequest]);
    expect(cubit.value(reply)!.count, 6);
    expect(cubit.value(target)!.count, 5);
  });
  test(
    'a response after session disposal does not emit to a closed Cubit',
    () async {
      final request = cubit.toggle(target, initial: initial);
      await cubit.close();
      repo.writes.single.result.complete(
        const LikeValue(isLiked: true, count: 5),
      );
      expect(await request, isNull);
    },
  );
}
