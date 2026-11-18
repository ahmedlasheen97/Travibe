import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/search/cubit/search_cubit.dart';
import 'package:travibe/features/search/data/recent_search.dart';
import 'package:travibe/features/search/data/users_page_model.dart';
import '../home/home_experience_fixtures.dart';
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
      expect(repo.recentTexts, ['@sarah']);
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
  group('recent searches', () {
    List<String> texts() => [
      for (final r in cubit.state.recentSearches) r.text,
    ];
    Future<void> submit(String query) async {
      cubit.onQueryChanged(query);
      cubit.submit();
      await settleRequests();
    }

    test('submitted queries are saved newest first', () async {
      await cubit.loadRecents();
      await submit('bali');
      await submit('cairo');
      expect(texts(), ['cairo', 'bali']);
      expect(repo.recentTexts, ['cairo', 'bali']);
    });

    test('duplicates ignore case and move to the top', () async {
      repo.recents = const [RecentSearch('Bali'), RecentSearch('Cairo')];
      await cubit.loadRecents();
      await submit('CAIRO');
      expect(texts(), ['CAIRO', 'Bali']);
    });

    test('keeps at most 10', () async {
      await cubit.loadRecents();
      for (var i = 0; i < 12; i++) {
        await submit('query $i');
      }
      expect(texts(), hasLength(10));
      expect(texts().first, 'query 11');
      expect(texts().last, 'query 2');
    });

    test('remove one and clear all', () async {
      repo.recents = const [RecentSearch('sarah'), RecentSearch('bali')];
      await cubit.loadRecents();
      await cubit.removeRecent(const RecentSearch('SARAH'));
      expect(texts(), ['bali']);
      expect(repo.recentTexts, ['bali']);
      await cubit.clearRecents();
      expect(cubit.state.recentSearches, isEmpty);
      expect(repo.recents, isEmpty);
    });

    test('selecting a query fills the field and searches', () async {
      repo.recents = const [RecentSearch('sarah'), RecentSearch('bali')];
      await cubit.loadRecents();
      cubit.selectRecent(const RecentSearch('bali'));
      await settleRequests();
      expect(cubit.searchController.text, 'bali');
      expect(repo.queries, ['bali:1']);
      expect(texts(), ['bali', 'sarah']);
    });

    test('opening a person saves @username with the user id', () async {
      await cubit.loadRecents();
      await cubit.recordPerson(suggested('7', username: 'sarah_travels'));
      expect(
        cubit.state.recentSearches.single,
        const RecentSearch('@sarah_travels', userId: '7'),
      );
    });

    test('history is kept per account', () async {
      repo.store['1'] = const [RecentSearch('mine')];
      repo.store['2'] = const [RecentSearch('theirs')];
      await cubit.loadRecents();
      expect(texts(), ['mine']);
      await submit('bali');
      expect(repo.store['2'], const [RecentSearch('theirs')]);

      final other = SearchCubit(repo: repo..userId = '2');
      addTearDown(other.close);
      await other.loadRecents();
      expect([for (final r in other.state.recentSearches) r.text], ['theirs']);
    });
  });
}
