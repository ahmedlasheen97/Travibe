import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/search/cubit/search_cubit.dart';
import 'package:travibe/features/search/data/users_page_model.dart';
import 'search_fixtures.dart';

void main() {
  late SearchFixture repo;
  late SearchCubit cubit;
  setUp(() {
    repo = SearchFixture();
    cubit = SearchCubit(repo: repo);
  });
  tearDown(() => cubit.close());

  test('empty, short and overlong queries make no API calls', () async {
    for (final query in ['', ' ', '@', 'ab', 'x' * 101]) {
      cubit.onQueryChanged(query);
      cubit.submit();
      await cubit.retry();
    }
    expect(repo.queries, isEmpty);
  });
  test(
    'submission strips @, loads people and stores recent searches',
    () async {
      cubit.onQueryChanged(' @sarah ');
      cubit.submit();
      await settleRequests();
      expect(repo.queries, ['sarah:1']);
      expect(cubit.state.status, SearchStatus.loaded);
      expect(cubit.state.people.single.name, 'Sarah Travels');
      expect(repo.recents, ['@sarah']);
    },
  );
  test('clear invalidates in-flight responses and pagination', () async {
    final result = Completer<UsersPageModel>();
    repo.handler = (_, _) => result.future;
    cubit.onQueryChanged('sarah');
    cubit.submit();
    cubit.clearQuery();
    result.complete(usersPage());
    await settleRequests();
    expect(cubit.state.query, isEmpty);
    expect(cubit.state.status, SearchStatus.idle);
    expect(cubit.state.people, isEmpty);
  });
  test('rapid changes hide old results and reject stale responses', () async {
    final first = Completer<UsersPageModel>();
    final second = Completer<UsersPageModel>();
    repo.handler = (term, _) => term == 'first' ? first.future : second.future;
    cubit.onQueryChanged('first');
    cubit.submit();
    cubit.onQueryChanged('second');
    expect(cubit.state.people, isEmpty);
    expect(cubit.state.status, SearchStatus.loading);
    cubit.submit();
    second.complete(usersPage(empty: true));
    await settleRequests();
    first.complete(usersPage());
    await settleRequests();
    expect(cubit.state.query, 'second');
    expect(cubit.state.people, isEmpty);
  });
  test('clean API error is retryable', () async {
    repo.handler = (_, _) async =>
        throw ApiError(message: 'Search unavailable');
    cubit.onQueryChanged('sarah');
    await cubit.retry();
    expect(cubit.state.status, SearchStatus.failure);
    expect(cubit.state.errorMessage, 'Search unavailable');
    repo.handler = null;
    await cubit.retry();
    expect(cubit.state.status, SearchStatus.loaded);
  });
  test(
    'pagination retains results, exposes failure, retries and deduplicates',
    () async {
      repo.handler = (_, page) async => page == 1
          ? usersPage(last: 2)
          : throw ApiError(message: 'Page failed');
      cubit.onQueryChanged('sarah');
      await cubit.retry();
      await cubit.loadMorePeople();
      expect(cubit.state.people, hasLength(1));
      expect(cubit.state.paginationError, 'Page failed');
      await cubit.loadMorePeople();
      expect(repo.queries, ['sarah:1', 'sarah:2']);
      repo.handler = (_, page) async => usersPage(page: page, last: 2);
      await cubit.loadMorePeople(retry: true);
      expect(cubit.state.paginationError, isEmpty);
      expect(cubit.state.people, hasLength(1));
      expect(cubit.state.hasMorePeople, isFalse);
    },
  );
  test('recent queries can be selected, removed and cleared', () async {
    repo.recents = ['sarah', 'bali'];
    cubit.loadRecents();
    cubit.selectRecent('sarah');
    await settleRequests();
    expect(cubit.searchController.text, 'sarah');
    expect(repo.queries, ['sarah:1']);
    await cubit.removeRecent('sarah');
    expect(cubit.state.recentSearches, ['bali']);
    await cubit.clearRecents();
    expect(repo.recents, isEmpty);
  });
}
