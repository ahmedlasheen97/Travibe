import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/search/cubit/search_cubit.dart';
import 'package:travibe/features/search/data/recent_search.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/search/data/search_repo.dart';

class SearchApi extends ApiService {
  final List<String> paths = [];
  Map<String, dynamic>? query;
  dynamic response = {
    'data': [],
    'meta': {'current_page': 2, 'last_page': 3, 'total': 30},
  };
  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
    paths.add(endpoint);
    query = queryParameters;
    return response;
  }
}

void main() {
  test('uses documented user search query and pagination', () async {
    final api = SearchApi();
    final page = await SearchRepo(
      apiService: api,
    ).searchUsers(' sarah ', page: 2);
    expect(api.paths, ['search/users']);
    expect(api.query, {'q': 'sarah', 'page': 2});
    expect(page.currentPage, 2);
    expect(page.hasMore, isTrue);
  });
  test('invalid queries never reach the API', () async {
    final api = SearchApi();
    final repo = SearchRepo(apiService: api);
    for (final value in ['', 'ab', 'x' * 101]) {
      await expectLater(repo.searchUsers(value), throwsA(isA<ApiError>()));
    }
    expect(api.paths, isEmpty);
  });
  test(
    'malformed responses fail instead of showing a false no-results state',
    () async {
      final api = SearchApi()..response = {'message': 'Invalid body'};
      await expectLater(
        SearchRepo(apiService: api).searchUsers('sarah'),
        throwsA(isA<ApiError>()),
      );
    },
  );
  test(
    'viewer identity does not require following_count or a list request',
    () async {
      final api = SearchApi()
        ..response = {
          'data': {'id': 9, 'name': 'Viewer'},
        };
      expect(await SearchRepo(apiService: api).getCurrentUserId(), '9');
      expect(api.paths, ['user']);
    },
  );

  group('local recent searches', () {
    final preferences = PreferencesManager();
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await preferences.init();
      await preferences.saveToken('account-a');
    });
    tearDown(() => preferences.clear());

    test('are stored per account and survive a reload', () async {
      final repo = SearchRepo(apiService: SearchApi());
      await repo.saveRecentSearches('1', const [
        RecentSearch('@sarah', userId: '9'),
        RecentSearch('bali'),
      ]);
      await repo.saveRecentSearches('2', const [RecentSearch('cairo')]);
      expect(SearchRepo().getRecentSearches('1'), const [
        RecentSearch('@sarah', userId: '9'),
        RecentSearch('bali'),
      ]);
      expect(SearchRepo().getRecentSearches('2'), const [
        RecentSearch('cairo'),
      ]);
      expect(SearchRepo().getRecentSearches('3'), isEmpty);
    });

    test('legacy plain strings parse; the ownerless key is dropped', () async {
      await preferences.setString('recent_searches', jsonEncode(['old']));
      await preferences.setString(
        '${SearchRepo.recentKeyPrefix}1',
        jsonEncode([
          'bali',
          42,
          {'text': '@sarah', 'user_id': 9},
        ]),
      );
      final repo = SearchRepo();
      expect(repo.getRecentSearches('1'), const [
        RecentSearch('bali'),
        RecentSearch('@sarah', userId: '9'),
      ]);
      await repo.saveRecentSearches('1', const [RecentSearch('bali')]);
      expect(preferences.getString('recent_searches'), isNull);
    });

    test('are cleared on logout', () async {
      await SearchRepo().saveRecentSearches('1', const [RecentSearch('bali')]);
      await preferences.clearSession();
      expect(SearchRepo().getRecentSearches('1'), isEmpty);
    });

    test('an account switch reloads the new account history', () async {
      final api = AccountApi()..id = 1;
      final repo = SearchRepo(apiService: api);
      await repo.saveRecentSearches('1', const [RecentSearch('mine')]);
      await repo.saveRecentSearches('2', const [RecentSearch('theirs')]);
      final cubit = SearchCubit(repo: repo);
      addTearDown(cubit.close);
      await cubit.loadRecents();
      expect(cubit.state.recentSearches, const [RecentSearch('mine')]);

      api.id = 2;
      await preferences.saveToken('account-b');
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.recentSearches, const [RecentSearch('theirs')]);
      expect(api.userReads, 2);
    });
  });
}

class AccountApi extends ApiService {
  int id = 1;
  int userReads = 0;
  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
    if (endpoint != 'user') throw StateError(endpoint);
    userReads++;
    return {
      'data': {'id': id, 'name': 'User $id'},
    };
  }
}
