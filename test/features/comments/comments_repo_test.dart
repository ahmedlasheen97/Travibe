import '../../helpers/cursor_fixtures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/comments/data/comment_model.dart';
import 'package:travibe/features/comments/data/comments_repo.dart';
import 'fixtures.dart';

class Api extends ApiService {
  String? method;
  String? path;
  Map<String, dynamic>? payload;
  dynamic response;
  ApiError? error;
  Future<dynamic> call(
    String method,
    String path,
    Map<String, dynamic>? payload,
  ) async {
    this.method = method;
    this.path = path;
    this.payload = payload;
    if (error != null) throw error!;
    return response;
  }

  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) => call('GET', endpoint, queryParameters);
  @override
  Future<dynamic> post(String endpoint, Map<String, dynamic> data) =>
      call('POST', endpoint, data);
  @override
  Future<dynamic> put(String endpoint, Map<String, dynamic> data) =>
      call('PUT', endpoint, data);
  @override
  Future<dynamic> delete(String endpoint) => call('DELETE', endpoint, null);
}

void main() {
  late Api api;
  late CommentsRepo repo;
  setUp(() {
    api = Api();
    repo = CommentsRepo(apiService: api);
  });
  test(
    'comment and reply share the documented nullable resource and permissions',
    () {
      final root = CommentModel.fromJson(commentJson(1, content: null));
      final ReplyModel reply = CommentModel.fromJson(
        commentJson(2, parentId: 1),
      );
      expect(root.content, isNull);
      expect(root.parentId, isNull);
      expect(reply.parentId, 1);
      expect(reply.permissions.canDelete, isTrue);
      expect(reply.user!.name, 'Sara');
      expect(reply.createdAt!.isUtc, isTrue);
    },
  );
  test('optional author/media/counts remain optional', () {
    final json = commentJson(1)
      ..remove('user')
      ..remove('media')
      ..remove('replies_count');
    final result = CommentModel.fromJson(json);
    expect(result.user, isNull);
    expect(result.media, isEmpty);
    expect(result.repliesCount, isNull);
  });
  test('missing permissions and malformed pagination are errors', () {
    final json = commentJson(1)..remove('permissions');
    expect(() => CommentModel.fromJson(json), throwsA(isA<ApiError>()));
    expect(() => CommentsPage.fromJson({'data': []}), throwsA(isA<ApiError>()));
  });
  for (final parent in [null, 1]) {
    test(
      'list parent=$parent uses exact query contract and page metadata',
      () async {
        api.response = {
          'data': [commentJson(2, parentId: parent)],
          'meta': cursorEnvelope(next: 'older|opaque==')['meta'],
        };
        final result = await repo.list(
          10,
          parentId: parent,
          cursor: 'next/+opaque==',
          perPage: 20,
        );
        expect(api.path, 'posts/10/comments');
        expect(api.payload, {
          'cursor': 'next/+opaque==',
          'per_page': 20,
          if (parent != null) 'parent_id': parent.toString(),
        });
        expect(result.hasMore, isTrue);
        expect(result.pagination.nextCursor, 'older|opaque==');
      },
    );
    test(
      'create parent=$parent sends text and optional integer parent only',
      () async {
        api.response = {'data': commentJson(2, parentId: parent)};
        await repo.create(10, CommentTextRequest(' Hello ', parentId: parent));
        expect(api.method, 'POST');
        expect(api.path, 'posts/10/comments');
        expect(
          api.payload,
          parent == null
              ? {'content': 'Hello'}
              : {'content': 'Hello', 'parent_id': parent},
        );
      },
    );
  }
  test('edit uses PUT, omitting parent and media IDs', () async {
    api.response = {'data': commentJson(2, parentId: 1, content: 'Edited')};
    await repo.edit(10, 2, const CommentTextRequest('Edited', parentId: 1));
    expect(api.method, 'PUT');
    expect(api.path, 'posts/10/comments/2');
    expect(api.payload, {'content': 'Edited'});
  });
  test(
    'delete is message-only 200 and restore returns the documented comment',
    () async {
      api.response = {'message': 'Deleted'};
      await repo.delete(10, 2);
      expect(api.method, 'DELETE');
      expect(api.path, 'posts/10/comments/2');
      api.response = {'data': commentJson(2)};
      final restored = await repo.restore(10, 2);
      expect(api.method, 'POST');
      expect(api.path, 'posts/10/comments/2/restore');
      expect(api.payload, isEmpty);
      expect(restored.id, 2);
    },
  );
  test(
    'single-comment and count reads use documented resource endpoints',
    () async {
      api.response = {'data': commentJson(2)};
      await repo.get(10, 2);
      expect(api.path, 'posts/10/comments/2');
      api.response = {
        'data': {'id': 10, 'comments_count': 9},
      };
      expect(await repo.commentCount(10), 9);
      expect(api.path, 'posts/10');
    },
  );
  test('absent counts and wrong thread/resource IDs are not guessed', () async {
    api.response = {
      'data': {'id': 10},
    };
    await expectLater(repo.commentCount(10), throwsA(isA<ApiError>()));
    api.response = {'data': commentJson(3)};
    await expectLater(repo.get(10, 2), throwsA(isA<ApiError>()));
    api.response = {
      'data': [commentJson(2, parentId: 1)],
      'meta': {'current_page': 1, 'last_page': 1, 'total': 1},
    };
    await expectLater(repo.list(10), throwsA(isA<ApiError>()));
  });
  test(
    'validation rejects blank/overlong text before making a request',
    () async {
      for (final text in ['  ', 'a' * 2001]) {
        await expectLater(
          repo.create(10, CommentTextRequest(text)),
          throwsA(isA<ApiError>()),
        );
      }
      expect(api.path, isNull);
      expect(CommentTextRequest('😀' * 2000).validationError, isNull);
    },
  );
  test(
    'backend 401/403/422 errors keep their original messages and status',
    () async {
      for (final status in [401, 403, 422]) {
        final error = ApiError(
          message: 'Backend restriction',
          statusCode: status,
        );
        api.error = error;
        await expectLater(repo.list(10), throwsA(same(error)));
        await expectLater(
          repo.create(10, const CommentTextRequest('Text')),
          throwsA(same(error)),
        );
        await expectLater(
          repo.edit(10, 2, const CommentTextRequest('Text')),
          throwsA(same(error)),
        );
        await expectLater(repo.delete(10, 2), throwsA(same(error)));
        await expectLater(repo.restore(10, 2), throwsA(same(error)));
      }
    },
  );
}
