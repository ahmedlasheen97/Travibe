import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/shares/cubit/send_post_cubit.dart';
import 'package:travibe/features/shares/data/share_post_messenger.dart';
import 'send_post_fixtures.dart';

void main() {
  late SendPeopleRepo repo;
  late RecordingChatRepository chat;
  late SendPostCubit cubit;
  setUp(() {
    repo = SendPeopleRepo();
    chat = RecordingChatRepository();
    cubit = SendPostCubit(
      post: sharedPost(),
      repo: repo,
      messenger: SharePostMessenger(chat: chat),
    );
  });
  tearDown(() => cubit.close());

  test(
    'suggestions coalesce; pagination deduplicates users and excludes blocks',
    () async {
      repo.hold = true;
      final first = cubit.load();
      await cubit.load();
      expect(repo.calls, hasLength(1));
      repo.calls.first.result.complete(
        peoplePage([person('2'), person('3', blocked: true)], last: 2),
      );
      await first;
      expect(cubit.state.users.map((u) => u.id), ['2']);
      final more = cubit.more();
      await cubit.more();
      expect(repo.calls, hasLength(2));
      expect(repo.calls.last.page, 2);
      repo.calls.last.result.complete(
        peoplePage([person('2'), person('4')], page: 2, last: 2),
      );
      await more;
      expect(cubit.state.users.map((u) => u.id), ['2', '4']);
      expect(cubit.state.hasMore, isFalse);
      await cubit.more();
      expect(repo.calls, hasLength(2));
    },
  );

  testWidgets(
    'stale suggestions and old searches cannot replace current query results',
    (tester) async {
      repo.hold = true;
      final initial = cubit.load();
      cubit.search('alice');
      await tester.pump(const Duration(milliseconds: 301));
      cubit.search('bobby');
      await tester.pump(const Duration(milliseconds: 301));
      expect(repo.calls.map((c) => c.query), ['', 'alice', 'bobby']);
      repo.calls.last.result.complete(peoplePage([person('4')]));
      await tester.pump();
      repo.calls[1].result.complete(peoplePage([person('8')]));
      repo.calls.first.result.complete(peoplePage([person('9')]));
      await initial;
      await tester.pump();
      expect(cubit.state.query, 'bobby');
      expect(cubit.state.users.single.id, '4');
    },
  );

  test('page failure retains people and retries the same page once', () async {
    repo.result = peoplePage([person('2')], last: 2);
    await cubit.load();
    repo.error = ApiError(message: 'Unavailable');
    await cubit.more();
    expect(cubit.state.users.single.id, '2');
    expect(cubit.state.error, 'Unavailable');
    repo.error = null;
    repo.result = peoplePage([person('3')], page: 2, last: 2);
    await cubit.more();
    expect(repo.calls.map((c) => c.page), [1, 2, 2]);
    expect(cubit.state.users.map((u) => u.id), ['2', '3']);
    expect(cubit.state.error, isNull);
  });

  test('incorrect page response becomes a retryable error', () async {
    repo.result = peoplePage([], page: 2, last: 2);
    await cubit.load();
    expect(cubit.state.error, isNotNull);
    expect(cubit.state.page, 0);
  });

  testWidgets(
    'invalid query cancels stale load; closing cancels debounced requests',
    (tester) async {
      cubit.search('alice');
      cubit.search('ab');
      await tester.pump(const Duration(milliseconds: 350));
      expect(repo.calls, isEmpty);
      expect(cubit.state.validQuery, isFalse);
      cubit.search('alice');
      await tester.runAsync(cubit.close);
      await tester.pump(const Duration(milliseconds: 350));
      expect(repo.calls, isEmpty);
    },
  );

  test('completion after closing emits nothing', () async {
    repo.hold = true;
    final load = cubit.load();
    await cubit.close();
    repo.calls.single.result.complete(peoplePage([person('2')]));
    await load;
    await Future<void>.delayed(Duration.zero);
    expect(cubit.isClosed, isTrue);
  });

  test('toggle selects several people and unselects on second tap', () async {
    await cubit.load();
    cubit.toggle(person('2'));
    cubit.toggle(person('3'));
    expect(cubit.state.selected.map((u) => u.id), ['2', '3']);
    cubit.toggle(person('2'));
    expect(cubit.state.selected.map((u) => u.id), ['3']);
    expect(cubit.state.isSelected('2'), isFalse);
  });

  testWidgets('selection survives searches and stays visible', (tester) async {
    await tester.runAsync(cubit.load);
    cubit.toggle(person('2'));
    repo.result = peoplePage([person('9')]);
    cubit.search('alice');
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pump();
    expect(cubit.state.users.map((u) => u.id), ['9']);
    expect(cubit.state.selected.map((u) => u.id), ['2']);
    expect(cubit.state.visibleUsers.map((u) => u.id), ['2', '9']);
  });

  test('send keeps only failed people selected with their errors', () async {
    await cubit.load();
    cubit.toggle(person('2'));
    cubit.toggle(person('3'));
    chat.failures['3'] = ApiError(message: 'Blocked', statusCode: 403);
    final sent = await cubit.send('hi');
    expect(sent!.map((u) => u.id), ['2']);
    expect(cubit.state.sending, isFalse);
    expect(cubit.state.selected.map((u) => u.id), ['3']);
    expect(cubit.state.failures, {'3': "You can't message Traveller 3."});
    chat.failures.clear();
    final retry = await cubit.send('hi');
    expect(retry!.map((u) => u.id), ['3']);
    expect(cubit.state.selected, isEmpty);
    expect(cubit.state.failures, isEmpty);
    expect(chat.created, ['2', '3', '3']);
  });

  test(
    'send ignores empty selection and duplicate taps; toggle locked while sending',
    () async {
      expect(await cubit.send(''), isNull);
      cubit.toggle(person('2'));
      chat.gate = Completer<void>();
      final first = cubit.send('');
      expect(await cubit.send(''), isNull);
      cubit.toggle(person('3'));
      expect(cubit.state.selected.map((u) => u.id), ['2']);
      chat.gate!.complete();
      await first;
      expect(chat.created, ['2']);
    },
  );
}
