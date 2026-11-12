import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/features/home/data/report_reason.dart';

class _ReportApi extends ApiService {
  final calls = <(String, Map<String, dynamic>)>[];
  Object? error;
  dynamic response = {
    'data': {'id': 1, 'status': 'pending'},
  };

  @override
  Future<dynamic> post(String endpoint, Map<String, dynamic> data) async {
    calls.add((endpoint, data));
    if (error != null) throw error!;
    return response;
  }
}

void main() {
  test('reasons map 1:1 to the documented API values', () {
    expect(ReportReason.values.map((r) => r.apiValue), [
      'spam_or_scam',
      'harassment',
      'inappropriate_content',
      'something_else',
    ]);
  });

  for (final reason in ReportReason.values) {
    test('reportPost sends type=post with ${reason.apiValue}', () async {
      final api = _ReportApi();
      await PostsRepo(apiService: api).reportPost('42', reason);
      expect(api.calls.single.$1, 'reports');
      expect(api.calls.single.$2, {
        'type': 'post',
        'id': 42,
        'reason': reason.apiValue,
      });
    });
  }

  test('description is trimmed, capped and omitted when blank', () async {
    final api = _ReportApi();
    final repo = PostsRepo(apiService: api);
    await repo.reportPost(
      '1',
      ReportReason.somethingElse,
      description: '  fake giveaway  ',
    );
    await repo.reportPost('1', ReportReason.somethingElse, description: '  ');
    await repo.reportPost(
      '1',
      ReportReason.somethingElse,
      description: 'x' * 1200,
    );
    expect(api.calls[0].$2['description'], 'fake giveaway');
    expect(api.calls[1].$2.containsKey('description'), isFalse);
    expect(api.calls[2].$2['description'], hasLength(1000));
  });

  test('invalid ids never reach the API', () {
    final api = _ReportApi();
    expect(
      () => PostsRepo(apiService: api).reportPost('x', ReportReason.harassment),
      throwsArgumentError,
    );
    expect(api.calls, isEmpty);
  });

  test('unconfirmed response is an error', () async {
    final api = _ReportApi()..response = {'message': 'ok'};
    expect(
      PostsRepo(apiService: api).reportPost('1', ReportReason.harassment),
      throwsA(isA<ApiError>()),
    );
  });

  test('ApiError passes through; duplicate 422 is detected', () async {
    final duplicate = ApiError(
      message: 'You have already reported this post.',
      statusCode: 422,
    );
    final api = _ReportApi()..error = duplicate;
    await expectLater(
      PostsRepo(apiService: api).reportPost('1', ReportReason.harassment),
      throwsA(same(duplicate)),
    );
    expect(isAlreadyReported(duplicate), isTrue);
    expect(
      isAlreadyReported(
        ApiError(
          message: 'Validation failed',
          statusCode: 422,
          fieldErrors: const {
            'id': ['A report for this post is still pending.'],
          },
        ),
      ),
      isTrue,
    );
    expect(
      isAlreadyReported(
        ApiError(message: 'The selected id is invalid.', statusCode: 422),
      ),
      isFalse,
    );
    expect(
      isAlreadyReported(ApiError(message: 'already', statusCode: 500)),
      isFalse,
    );
  });
}
