import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/comments/cubit/comments_cubit.dart';
import 'fixtures.dart';

void main() {
  late MemoryCommentsRepo repo;
  late CommentsCubit cubit;
  late List<int> counts;
  setUp(() {
    repo = MemoryCommentsRepo();
    counts = [];
    cubit = CommentsCubit(postId: 10, repo: repo, onCountChanged: counts.add);
  });
  tearDown(() => cubit.close());
  test(
    'initial load coalesces duplicate requests and renders empty success',
    () async {
      repo.holdReads = true;
      final a = cubit.load();
      final b = cubit.load();
      expect(cubit.state.thread(null).status, CommentsStatus.loading);
      expect(repo.reads, hasLength(1));
      repo.reads.single.result.complete(page([]));
      await Future.wait([a, b]);
      expect(cubit.state.thread(null).status, CommentsStatus.loaded);
      expect(cubit.state.thread(null).comments, isEmpty);
      await cubit.more();
      expect(repo.reads, hasLength(1));
    },
  );
  test('root and reply threads load/paginate independently', () async {
    repo.items.addAll({
      1: comment(1),
      2: comment(2),
      3: comment(3),
      4: comment(4, parentId: 1),
      5: comment(5, parentId: 1),
      6: comment(6, parentId: 1),
    });
    await cubit.load();
    await cubit.load(parentId: 1);
    await cubit.more(parentId: 1);
    expect(cubit.state.thread(null).nextCursor, 'next/+opaque==');
    expect(cubit.state.thread(1).nextCursor, isNull);
    expect(cubit.state.thread(1).comments, hasLength(3));
    expect(cubit.state.thread(null).comments, hasLength(2));
  });
  test(
    'pagination prevents duplicate calls, deduplicates IDs and stops',
    () async {
      repo.items.addAll({1: comment(1), 2: comment(2), 3: comment(3)});
      await cubit.load();
      repo.holdReads = true;
      final more = cubit.more();
      await cubit.more();
      expect(repo.reads, hasLength(2));
      expect(repo.reads.last.page, 2);
      repo.reads.last.result.complete(
        page([comment(2), comment(1)], current: 2, last: 2),
      );
      await more;
      expect(cubit.state.thread(null).comments.map((c) => c.id), [3, 2, 1]);
      await cubit.more();
      expect(repo.reads, hasLength(2));
    },
  );
  test('load failure preserves backend error and retries', () async {
    final error = ApiError(message: 'Forbidden', statusCode: 403);
    repo.readError = error;
    await cubit.load();
    expect(cubit.state.thread(null).status, CommentsStatus.failure);
    expect(cubit.state.thread(null).error, same(error));
    repo.readError = null;
    await cubit.load();
    expect(cubit.state.thread(null).status, CommentsStatus.loaded);
  });
  test('pagination failure retains rows and requires explicit retry', () async {
    repo.items.addAll({1: comment(1), 2: comment(2), 3: comment(3)});
    await cubit.load();
    final error = ApiError(message: 'Try later', statusCode: 429);
    repo.readError = error;
    await cubit.more();
    expect(cubit.state.thread(null).paginationError, same(error));
    expect(cubit.state.thread(null).comments, hasLength(2));
    final length = repo.reads.length;
    await cubit.more();
    expect(repo.reads, hasLength(length));
    repo.readError = null;
    await cubit.more(retry: true);
    expect(repo.reads.last.page, 2);
    expect(cubit.state.thread(null).paginationError, isNull);
  });
  test(
    'refresh supersedes an older page and clears pagination failures',
    () async {
      repo.items.addAll({1: comment(1), 2: comment(2), 3: comment(3)});
      await cubit.load();
      repo.holdReads = true;
      final more = cubit.more();
      final old = repo.reads.last;
      final refresh = cubit.load();
      repo.reads.last.result.complete(page([comment(9)]));
      await refresh;
      old.result.complete(page([comment(1)], current: 2));
      await more;
      expect(cubit.state.thread(null).comments.single.id, 9);
    },
  );
  test(
    'refresh failure retains existing data and pagination position',
    () async {
      repo.items[1] = comment(1);
      await cubit.load();
      repo.readError = ApiError(message: 'Offline');
      await cubit.load();
      expect(cubit.state.thread(null).status, CommentsStatus.loaded);
      expect(cubit.state.thread(null).comments.single.id, 1);
      expect(cubit.state.thread(null).refreshing, isFalse);
      expect(cubit.state.thread(null).error, isNotNull);
    },
  );
  test(
    'create updates the root list and uses authoritative count callback',
    () async {
      repo.items[1] = comment(1);
      await cubit.load();
      final result = await cubit.create(' New comment ');
      expect(result.confirmed, isTrue);
      expect(result.comment!.content, 'New comment');
      expect(cubit.state.thread(null).comments.first.id, 100);
      expect(cubit.state.count, 2);
      expect(counts, [2]);
      expect(cubit.state.busy, isFalse);
    },
  );
  test(
    'reply creation updates its thread, parent reply count and post count',
    () async {
      repo.items[1] = comment(1);
      await cubit.load();
      await cubit.load(parentId: 1);
      final result = await cubit.create('Reply', parentId: 1);
      expect(result.comment!.parentId, 1);
      expect(cubit.state.thread(1).comments.single.content, 'Reply');
      expect(cubit.state.thread(null).comments.single.repliesCount, 1);
      expect(cubit.state.count, 2);
      expect(counts, [2]);
    },
  );
  test(
    'duplicate submissions/mutations are ignored while a write is pending',
    () async {
      await cubit.load();
      repo.writeGate = Completer<void>();
      final request = cubit.create('Once');
      final duplicate = await cubit.create('Once');
      expect(duplicate.confirmed, isFalse);
      expect(cubit.state.busy, isTrue);
      expect(repo.writes, ['create']);
      repo.writeGate!.complete();
      expect((await request).confirmed, isTrue);
      expect(repo.items, hasLength(1));
      expect(counts, [1]);
    },
  );
  test('validation does not send blank or overlong text', () async {
    expect((await cubit.create('  ')).error, isNotNull);
    expect((await cubit.create('a' * 2001)).error, isNotNull);
    expect(repo.writes, isEmpty);
  });
  test(
    'edit applies confirmed text and does not invent a count change',
    () async {
      repo.items[1] = comment(1);
      await cubit.load();
      final result = await cubit.edit(comment(1), 'Edited');
      expect(result.confirmed, isTrue);
      expect(cubit.state.thread(null).comments.single.content, 'Edited');
      expect(repo.countCalls, 0);
      expect(counts, isEmpty);
    },
  );
  test('permission flags prohibit edit/delete without a request', () async {
    final locked = comment(1, canEdit: false, canDelete: false);
    repo.items[1] = locked;
    await cubit.load();
    expect((await cubit.edit(locked, 'Edit')).error, isNotNull);
    expect((await cubit.delete(locked)).error, isNotNull);
    expect(repo.writes, isEmpty);
  });
  for (final operation in ['create', 'edit', 'delete', 'restore']) {
    test('$operation failure retains data and exact backend status', () async {
      repo.items[1] = comment(1);
      await cubit.load();
      if (operation == 'restore') await cubit.delete(comment(1));
      final countBefore = cubit.state.count;
      final error = ApiError(message: 'Backend restriction', statusCode: 422);
      repo.mutationError = error;
      final result = switch (operation) {
        'create' => await cubit.create('Text'),
        'edit' => await cubit.edit(comment(1), 'Text'),
        'delete' => await cubit.delete(comment(1)),
        _ => await cubit.restore(1),
      };
      expect(result.confirmed, isFalse);
      expect(result.error, same(error));
      expect(cubit.state.count, countBefore);
      expect(cubit.state.busy, isFalse);
      expect(
        cubit.state.thread(null).comments.length,
        operation == 'restore' ? 0 : 1,
      );
    });
  }
  test(
    'delete uses server count for cascades; restore restores only the selected comment',
    () async {
      repo.cascade = true;
      repo.items.addAll({1: comment(1), 2: comment(2, parentId: 1)});
      await cubit.load();
      expect((await cubit.delete(comment(1))).confirmed, isTrue);
      expect(cubit.state.thread(null).comments, isEmpty);
      expect(cubit.state.count, 0);
      expect((await cubit.restore(1)).confirmed, isTrue);
      expect(cubit.state.thread(null).comments.single.id, 1);
      expect(cubit.state.count, 1);
      expect(repo.deleted.containsKey(2), isTrue);
      expect(counts, [0, 1]);
    },
  );
  test('a confirmed mutation supersedes an earlier initial read', () async {
    repo.holdReads = true;
    final initial = cubit.load();
    final old = repo.reads.last;
    final create = cubit.create('New');
    await Future<void>.delayed(Duration.zero);
    expect(repo.reads, hasLength(2));
    repo.reads.last.result.complete(page([comment(100, content: 'New')]));
    await create;
    old.result.complete(page([]));
    await initial;
    expect(cubit.state.thread(null).comments.single.id, 100);
  });
  test(
    'count refresh failure retains confirmed write and supports separate retry',
    () async {
      await cubit.load();
      final error = ApiError(message: 'Count unavailable', statusCode: 503);
      repo.countError = error;
      final result = await cubit.create('Text');
      expect(result.confirmed, isTrue);
      expect(cubit.state.syncError, same(error));
      expect(repo.writes, ['create']);
      repo.countError = null;
      await cubit.synchronize();
      expect(cubit.state.count, 1);
      expect(cubit.state.syncError, isNull);
      expect(repo.writes, ['create']);
    },
  );
  test(
    'stale metadata retry cannot overwrite a newer mutation count',
    () async {
      await cubit.load();
      repo.holdCounts = true;
      final old = cubit.synchronize();
      final create = cubit.create('New');
      await Future<void>.delayed(Duration.zero);
      expect(repo.counts, hasLength(2));
      repo.counts[1].complete(1);
      await create;
      repo.counts[0].complete(0);
      await old;
      expect(cubit.state.count, 1);
      expect(counts, [1]);
    },
  );
  test('late list responses after disposal are ignored', () async {
    repo.holdReads = true;
    final request = cubit.load();
    await cubit.close();
    repo.reads.single.result.complete(page([comment(1)]));
    await request;
    expect(cubit.state.thread(null).status, CommentsStatus.loading);
  });
  test(
    'a write finishing after disposal still synchronizes the mounted feed callback',
    () async {
      repo.writeGate = Completer<void>();
      final create = cubit.create('New');
      await cubit.close();
      repo.writeGate!.complete();
      expect((await create).confirmed, isTrue);
      expect(counts, [1]);
    },
  );
  for (final operation in ['edit', 'delete', 'restore']) {
    test(
      'duplicate $operation requests are ignored until the first finishes',
      () async {
        repo.items[1] = comment(1);
        await cubit.load();
        if (operation == 'restore') await cubit.delete(comment(1));
        repo.writes.clear();
        repo.writeGate = Completer<void>();
        Future<CommentMutationResult> perform() => switch (operation) {
          'edit' => cubit.edit(comment(1), 'Edit'),
          'delete' => cubit.delete(comment(1)),
          _ => cubit.restore(1),
        };
        final first = perform();
        final second = await perform();
        expect(second.confirmed, isFalse);
        expect(repo.writes, [operation]);
        repo.writeGate!.complete();
        expect((await first).confirmed, isTrue);
      },
    );
  }
}
