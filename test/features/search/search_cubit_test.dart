import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/search/cubit/search_cubit.dart';
import 'package:travibe/features/search/data/recent_search.dart';
import 'package:travibe/features/home/data/posts_page_model.dart';
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
    expect(repo.postQueries, isEmpty);
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
    cubit.setTab(SearchTab.people);
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
    cubit.setTab(SearchTab.people);
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
      cubit.setTab(SearchTab.people);
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
  group('posts', () {
    test('Posts is the default tab; a query searches posts only', () async {
      repo.postsHandler = (_, page) async => postsPage([1, 2]);
      expect(cubit.state.tab, SearchTab.posts);
      cubit.onQueryChanged('bali');
      expect(cubit.state.postsStatus, SearchStatus.loading);
      cubit.submit();
      await settleRequests();
      expect(repo.postQueries, ['posts:bali:1']);
      expect(repo.queries, isEmpty);
      expect(cubit.state.postsStatus, SearchStatus.loaded);
      expect([for (final p in cubit.state.posts) p.id], ['1', '2']);
    });

    test('debounced typing searches the visible tab once', () async {
      cubit.onQueryChanged('bal');
      cubit.onQueryChanged('bali');
      expect(repo.postQueries, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect(repo.postQueries, ['posts:bali:1']);
    });

    test('switching tabs loads each tab once per term', () async {
      cubit.onQueryChanged('bali');
      cubit.submit();
      await settleRequests();
      cubit.setTab(SearchTab.people);
      await settleRequests();
      cubit.setTab(SearchTab.posts);
      cubit.setTab(SearchTab.people);
      await settleRequests();
      expect(repo.postQueries, ['posts:bali:1']);
      expect(repo.queries, ['bali:1']);
      // A new term invalidates both; only the visible tab reloads.
      cubit.onQueryChanged('cairo');
      cubit.submit();
      await settleRequests();
      expect(repo.queries, ['bali:1', 'cairo:1']);
      expect(repo.postQueries, ['posts:bali:1']);
    });

    test('"@" queries switch to People', () async {
      cubit.onQueryChanged('@sarah');
      cubit.submit();
      await settleRequests();
      expect(cubit.state.tab, SearchTab.people);
      expect(repo.postQueries, isEmpty);
    });

    test('empty results load as empty, not as an error', () async {
      cubit.onQueryChanged('nothing here');
      cubit.submit();
      await settleRequests();
      expect(cubit.state.postsStatus, SearchStatus.loaded);
      expect(cubit.state.posts, isEmpty);
      expect(cubit.state.hasMorePosts, isFalse);
    });

    test('failure is retryable', () async {
      repo.postsHandler = (_, _) async => throw ApiError(message: 'Down');
      cubit.onQueryChanged('bali');
      await cubit.retry();
      expect(cubit.state.postsStatus, SearchStatus.failure);
      expect(cubit.state.postsError, 'Down');
      repo.postsHandler = (_, _) async => postsPage([1]);
      await cubit.retry();
      expect(cubit.state.postsStatus, SearchStatus.loaded);
      expect(cubit.state.posts, hasLength(1));
    });

    test('paging appends, deduplicates, retries and stops', () async {
      repo.postsHandler = (_, page) async => page == 1
          ? postsPage([1, 2], last: 2)
          : throw ApiError(message: 'Page failed');
      cubit.onQueryChanged('bali');
      await cubit.retry();
      expect(cubit.state.hasMorePosts, isTrue);
      await cubit.loadMorePosts();
      expect(cubit.state.postsPaginationError, 'Page failed');
      await cubit.loadMorePosts(); // no automatic retry after a failure
      expect(repo.postQueries, ['posts:bali:1', 'posts:bali:2']);
      repo.postsHandler = (_, page) async =>
          postsPage([2, 3], page: page, last: 2);
      await cubit.loadMorePosts(retry: true);
      expect([for (final p in cubit.state.posts) p.id], ['1', '2', '3']);
      expect(cubit.state.hasMorePosts, isFalse);
      expect(cubit.state.postsPaginationError, isEmpty);
      await cubit.loadMorePosts();
      expect(repo.postQueries, hasLength(3));
    });

    test('a stale page is dropped after the query changes', () async {
      final page = Completer<PostsPageModel>();
      repo.postsHandler = (term, _) async =>
          term == 'bali' ? page.future : postsPage(const []);
      cubit.onQueryChanged('bali');
      cubit.submit();
      cubit.onQueryChanged('cairo');
      cubit.submit();
      await settleRequests();
      page.complete(postsPage([1]));
      await settleRequests();
      expect(cubit.state.query, 'cairo');
      expect(cubit.state.posts, isEmpty);
    });

    test('clearing the query drops results without a request', () async {
      repo.postsHandler = (_, _) async => postsPage([1]);
      cubit.onQueryChanged('bali');
      cubit.submit();
      await settleRequests();
      cubit.clearQuery();
      expect(cubit.state.posts, isEmpty);
      expect(cubit.state.postsStatus, SearchStatus.idle);
      expect(repo.postQueries, ['posts:bali:1']);
    });
  });
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
      expect(repo.postQueries, ['posts:bali:1']);
      expect(repo.queries, isEmpty);
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
