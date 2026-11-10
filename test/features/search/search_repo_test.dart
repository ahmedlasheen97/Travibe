import 'package:flutter_test/flutter_test.dart';
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
}
