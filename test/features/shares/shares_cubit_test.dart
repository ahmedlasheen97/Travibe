import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/shares/cubit/shares_cubit.dart';
import 'package:travibe/features/shares/data/share_model.dart';
import 'fixtures.dart';

void main() {
  late MemorySharesRepo repo;
  late SharesCubit cubit;
  setUp(() {
    repo = MemorySharesRepo();
    cubit = SharesCubit(repo: repo);
    cubit.acceptCounts({10: 2}, requestRevision: 0);
  });
  tearDown(() => cubit.close());

  test(
    'read cleanup completes and allows subsequent ownership and count checks',
    () async {
      await cubit.inspect(10).timeout(const Duration(seconds: 1));
      await cubit.inspect(10, force: true).timeout(const Duration(seconds: 1));
      expect(repo.reads, hasLength(2));
      await cubit.refreshCount(10).timeout(const Duration(seconds: 1));
      repo.counts[10] = 8;
      await cubit.refreshCount(10).timeout(const Duration(seconds: 1));
      expect(cubit.post(10).count, 8);
      expect(repo.creates, isEmpty);
      expect(repo.deletes, isEmpty);
    },
  );

  test(
    'ownership check exhausts pagination and caches the current user share',
    () async {
      repo.records[10] = [
        share(id: 1, userId: 2),
        share(id: 2, userId: 3),
        share(),
      ];
      await cubit.inspect(10);
      expect(repo.reads.map((r) => r.page), [1, 2]);
      expect(cubit.canDelete(10), isTrue);
      expect(cubit.post(10).ownShare!.id, 73);
      expect(
        cubit.post(10).count,
        2,
      ); // List total is 3, not the post's share count.
      await cubit.inspect(10);
      expect(repo.reads, hasLength(2));
      expect(repo.identityReads, 1);
    },
  );
  test(
    'empty lists mean no own share, and overlapping checks coalesce',
    () async {
      repo.holdReads = true;
      final first = cubit.inspect(10);
      final second = cubit.inspect(10);
      expect(identical(first, second), isTrue);
      await flushShares();
      expect(cubit.post(10).loading, isTrue);
      expect(repo.reads, hasLength(1));
      repo.reads.single.result.complete(
        SharesPage(shares: [], currentPage: 1, lastPage: 1, total: 0),
      );
      await first;
      expect(cubit.post(10).ownershipKnown, isTrue);
      expect(cubit.post(10).ownShare, isNull);
      expect(cubit.canDelete(10), isFalse);
    },
  );
  test('create is confirmed once and reconciles authoritative count', () async {
    await cubit.inspect(10);
    repo.createGate = Completer<ShareModel>();
    repo.countGate = Completer<int>();
    final request = cubit.create(
      10,
      const CreateShareRequest(comment: 'Caption'),
    );
    await cubit.create(10, const CreateShareRequest());
    expect(repo.creates, hasLength(1));
    expect(cubit.post(10).pending, isTrue);
    expect(cubit.post(10).count, 2); // No count change before confirmation.
    repo.createGate!.complete(share(comment: 'Caption'));
    await flushShares();
    expect(cubit.post(10).count, 3);
    expect(cubit.post(10).ownShare!.id, 73);
    repo.countGate!.complete(9);
    expect((await request).confirmed, isTrue);
    expect(cubit.post(10).count, 9);
    expect(cubit.post(10).pending, isFalse);
  });
  test('delete uses owned share ID and prevents duplicate deletes', () async {
    repo.records[10] = [share(), share(id: 88, userId: 8)];
    await cubit.inspect(10);
    repo.deleteGate = Completer<void>();
    final request = cubit.delete(10);
    await cubit.delete(10);
    expect(repo.deletes, [(postId: 10, shareId: 73)]);
    repo.deleteGate!.complete();
    expect((await request).removed, isTrue);
    expect(cubit.post(10).ownShare, isNull);
    expect(cubit.post(10).count, 1);
    expect(repo.records[10]!.single.id, 88);
  });
  test(
    'foreign shares cannot be deleted and known duplicates do not POST',
    () async {
      repo.records[10] = [share(userId: 8)];
      await cubit.inspect(10);
      expect((await cubit.delete(10)).error, isNotNull);
      expect(repo.deletes, isEmpty);
      repo.records[10] = [share()];
      await cubit.inspect(10, force: true);
      expect(
        (await cubit.create(10, const CreateShareRequest())).error,
        isNotNull,
      );
      expect(repo.creates, isEmpty);
    },
  );
  for (final status in [401, 403, 404, 422, null]) {
    test(
      'create failure $status preserves count and requires status check before retry',
      () async {
        await cubit.inspect(10);
        final error = ApiError(message: 'Share failed', statusCode: status);
        repo.createError = error;
        final result = await cubit.create(10, const CreateShareRequest());
        expect(result.error, same(error));
        expect(result.confirmed, isFalse);
        expect(cubit.post(10).count, 2);
        expect(cubit.post(10).ownershipKnown, isFalse);
        await cubit.create(10, const CreateShareRequest());
        expect(repo.creates, hasLength(1));
        repo.createError = null;
        await cubit.inspect(10, force: true);
        expect(
          (await cubit.create(10, const CreateShareRequest())).confirmed,
          isTrue,
        );
      },
    );
  }
  test(
    'ambiguous timeout or duplicate 422 can recover an existing share without another POST',
    () async {
      await cubit.inspect(10);
      repo.createError = ApiError(message: 'Request timed out');
      await cubit.create(10, const CreateShareRequest());
      repo.records[10] = [share()];
      repo.counts[10] = 3;
      // Reopening the dialog must also reconcile an ambiguous write, even
      // without explicitly pressing its Retry action.
      await cubit.inspect(10);
      expect(cubit.canDelete(10), isTrue);
      expect(cubit.post(10).count, 3);
      expect(repo.creates, hasLength(1));
    },
  );
  test(
    'delete failure keeps count; already-deleted 404 is reconciled through list',
    () async {
      repo.records[10] = [share()];
      await cubit.inspect(10);
      repo.deleteError = ApiError(message: 'Not found', statusCode: 404);
      expect((await cubit.delete(10)).confirmed, isFalse);
      expect(cubit.post(10).count, 2);
      expect(cubit.canDelete(10), isFalse);
      repo.records[10] = [];
      repo.counts[10] = 1;
      await cubit.inspect(10, force: true);
      expect(cubit.post(10).ownShare, isNull);
      expect(cubit.post(10).count, 1);
      expect(repo.deletes, hasLength(1));
    },
  );
  test('confirmed write with failed count sync retries GET only', () async {
    await cubit.inspect(10);
    repo.countError = ApiError(message: 'Network failed');
    final result = await cubit.create(10, const CreateShareRequest());
    expect(result.confirmed, isTrue);
    expect(result.error, isNotNull);
    expect(cubit.post(10).count, 3);
    expect(cubit.canDelete(10), isTrue);
    repo.countError = null;
    await cubit.refreshCount(10);
    expect(cubit.post(10).syncError, isNull);
    expect(repo.creates, hasLength(1));
  });
  test('stale counts cannot overwrite a pending or confirmed write', () async {
    await cubit.inspect(10);
    final old = cubit.revision;
    repo.createGate = Completer<ShareModel>();
    final request = cubit.create(10, const CreateShareRequest());
    cubit.acceptCounts({10: 100}, requestRevision: cubit.revision);
    expect(cubit.post(10).count, 2);
    repo.createGate!.complete(share());
    await request;
    cubit.acceptCounts({10: 2}, requestRevision: old);
    expect(cubit.post(10).count, 3);
    cubit.acceptCounts({10: 5}, requestRevision: cubit.revision);
    expect(cubit.post(10).count, 5);
  });
  test(
    'external record deletion does not decrement internal share count',
    () async {
      repo.records[10] = [share(platform: 'copy_link')];
      await cubit.inspect(10);
      expect((await cubit.delete(10)).confirmed, isTrue);
      expect(cubit.post(10).count, 2);
    },
  );
  test(
    'permission-denied deletion preserves data and prevents a guessed retry',
    () async {
      repo.records[10] = [share()];
      await cubit.inspect(10);
      repo.deleteError = ApiError(message: 'Forbidden', statusCode: 403);
      final result = await cubit.delete(10);
      expect(result.error!.statusCode, 403);
      expect(cubit.post(10).count, 2);
      expect(cubit.post(10).ownShare!.id, 73);
      await cubit.delete(10);
      expect(repo.deletes, hasLength(1));
    },
  );
  test(
    'invalid creation ID cannot enable Unshare or manufacture a count',
    () async {
      await cubit.inspect(10);
      repo.createGate = Completer<ShareModel>();
      final request = cubit.create(10, const CreateShareRequest());
      repo.createGate!.complete(
        const ShareModel(
          id: 0,
          userId: 7,
          postId: 10,
          platform: SharePlatform.internal,
        ),
      );
      expect((await request).confirmed, isFalse);
      expect(cubit.post(10).ownShare, isNull);
      expect(cubit.post(10).count, 2);
      expect(cubit.canDelete(10), isFalse);
      expect(repo.deletes, isEmpty);
    },
  );
  test('unshare never makes a count negative', () async {
    repo.records[10] = [share()];
    repo.counts[10] = 0;
    cubit.acceptCounts({10: 0}, requestRevision: 0);
    await cubit.inspect(10);
    await cubit.delete(10);
    expect(cubit.post(10).count, 0);
  });
  test(
    'authentication and shares-list failures have a successful retry path',
    () async {
      repo.identityError = ApiError(
        message: 'Unauthenticated',
        statusCode: 401,
      );
      await cubit.inspect(10);
      expect(cubit.post(10).error!.statusCode, 401);
      expect(cubit.post(10).ownershipKnown, isFalse);
      repo.identityError = null;
      repo.listError = ApiError(message: 'Post unavailable', statusCode: 404);
      await cubit.inspect(10, force: true);
      expect(cubit.post(10).error!.statusCode, 404);
      repo.listError = null;
      await cubit.inspect(10, force: true);
      expect(cubit.post(10).ownershipKnown, isTrue);
      expect(cubit.post(10).error, isNull);
    },
  );
}
