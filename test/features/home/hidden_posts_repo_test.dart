import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/home/data/posts_repo.dart';

class HiddenApi extends ApiService {
  String? method;
  String? path;
  Map<String, dynamic>? body;
  dynamic response;
  ApiError? error;

  @override
  Future<dynamic> post(String endpoint, Map<String, dynamic> data) async {
    method = 'POST';
    path = endpoint;
    body = data;
    if (error != null) throw error!;
    return response;
  }

  @override
  Future<dynamic> delete(String endpoint) async {
    method = 'DELETE';
    path = endpoint;
    if (error != null) throw error!;
    return response;
  }
}

void main() {
  for (final hidden in [true, false]) {
    test(
      '${hidden ? 'hide' : 'unhide'} uses documented method/path and flat response',
      () async {
        final api = HiddenApi()
          ..response = {'is_hidden': hidden, 'message': 'Done'};
        final result = await PostsRepo(apiService: api).setHidden('7', hidden);
        expect(api.method, hidden ? 'POST' : 'DELETE');
        expect(api.path, 'posts/7/hide');
        expect(api.body, hidden ? isEmpty : isNull);
        expect(result.isHidden, hidden);
        expect(result.message, 'Done');
      },
    );
    test(
      '${hidden ? 'hide' : 'unhide'} preserves backend errors and status',
      () async {
        final error = ApiError(message: 'Forbidden', statusCode: 403);
        final api = HiddenApi()..error = error;
        await expectLater(
          PostsRepo(apiService: api).setHidden('7', hidden),
          throwsA(same(error)),
        );
      },
    );
  }
  test('malformed or unconfirmed response cannot change feed state', () async {
    final api = HiddenApi();
    final repo = PostsRepo(apiService: api);
    for (final json in [
      null,
      {
        'data': {'is_hidden': true},
      },
      {'is_hidden': 'true', 'message': 'Done'},
      {'is_hidden': true},
      {'is_hidden': false, 'message': 'Done'},
    ]) {
      api.response = json;
      await expectLater(repo.setHidden('7', true), throwsA(isA<ApiError>()));
    }
  });
  test('invalid post ID is rejected before networking', () async {
    final api = HiddenApi();
    await expectLater(
      PostsRepo(apiService: api).setHidden('invalid', true),
      throwsArgumentError,
    );
    expect(api.method, isNull);
  });
}
