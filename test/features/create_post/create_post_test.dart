import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/create_post/cubit/create_post_cubit.dart';
import 'package:travibe/features/create_post/data/create_post_repo.dart';
import 'package:travibe/features/create_post/data/create_post_request.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'fixtures.dart';

class Api extends ApiService {
  String? endpoint;
  Map<String, dynamic>? body;
  ApiError? error;
  dynamic response = {'data': postJson()};
  @override
  Future<dynamic> post(String endpoint, Map<String, dynamic> data) async {
    this.endpoint = endpoint;
    body = data;
    if (error != null) throw error!;
    return response;
  }

  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
    this.endpoint = endpoint;
    return {
      'data': {'id': 7, 'name': 'Sara', 'username': 'sara', 'avatar_url': null},
    };
  }
}

void main() {
  test('serializes only documented fields for every supported audience', () {
    for (final visibility in PostVisibility.values) {
      expect(
        CreatePostRequest(
          content: '  A trip\nNext stop  ',
          visibility: visibility,
        ).toJson(),
        {'content': 'A trip\nNext stop', 'visibility': visibility.name},
      );
    }
  });
  test(
    'validates empty text and 2000 Unicode characters without splitting emojis',
    () {
      for (final text in ['', ' \n\t']) {
        expect(
          () => CreatePostRequest(content: text).toJson(),
          throwsA(isA<ApiError>()),
        );
      }
      expect(CreatePostRequest(content: '😀' * 2000).characterCount, 2000);
      expect(CreatePostRequest(content: '😀' * 2000).validationError, isNull);
      expect(
        () => CreatePostRequest(content: '😀' * 2001).toJson(),
        throwsA(isA<ApiError>()),
      );
    },
  );
  test('uses POST posts and parses the data envelope', () async {
    final api = Api();
    final post = await CreatePostRepo(apiService: api).create(
      const CreatePostRequest(
        content: 'A trip',
        visibility: PostVisibility.private,
      ),
    );
    expect(api.endpoint, 'posts');
    expect(api.body, {'content': 'A trip', 'visibility': 'private'});
    expect(post.id, '42');
  });
  test('rejects invalid input before contacting the API', () async {
    final api = Api();
    await expectLater(
      CreatePostRepo(
        apiService: api,
      ).create(const CreatePostRequest(content: ' ')),
      throwsA(isA<ApiError>()),
    );
    expect(api.endpoint, isNull);
  });
  test(
    'preserves validation and network error messages and status codes',
    () async {
      for (final failure in [
        ApiError(message: 'Content is invalid', statusCode: 422),
        ApiError(message: 'Connection timeout'),
      ]) {
        final api = Api()..error = failure;
        await expectLater(
          CreatePostRepo(
            apiService: api,
          ).create(const CreatePostRequest(content: 'Trip')),
          throwsA(same(failure)),
        );
      }
    },
  );
  test(
    'rejects malformed success instead of reporting publication success',
    () async {
      final api = Api()..response = {'data': []};
      await expectLater(
        CreatePostRepo(
          apiService: api,
        ).create(const CreatePostRequest(content: 'Trip')),
        throwsA(isA<ApiError>()),
      );
    },
  );
  test(
    'loads actual composer identity from documented user endpoint',
    () async {
      final api = Api();
      final author = await CreatePostRepo(apiService: api).getCurrentAuthor();
      expect(api.endpoint, 'user');
      expect(author.name, 'Sara');
      expect(author.username, 'sara');
    },
  );
  test(
    'duplicate submissions and edits cannot change a pending request',
    () async {
      final repo = MemoryCreatePostRepo()..gate = Completer<PostModel>();
      final cubit = CreatePostCubit(repo: repo);
      addTearDown(cubit.close);
      cubit.setContent('Original draft');
      cubit.setVisibility(PostVisibility.followers);
      final pending = cubit.submit();
      await cubit.submit();
      cubit.setContent('Changed');
      cubit.setVisibility(PostVisibility.private);
      expect(cubit.state.status, CreatePostStatus.submitting);
      expect(repo.requests, hasLength(1));
      expect(repo.requests.single.content, 'Original draft');
      expect(repo.requests.single.visibility, PostVisibility.followers);
      repo.gate!.complete(PostModel.fromJson(postJson()));
      await pending;
      expect(cubit.state.status, CreatePostStatus.success);
      await cubit.submit();
      expect(repo.requests, hasLength(1));
    },
  );
  test(
    'failure retains draft and audience and supports explicit retry',
    () async {
      final repo = MemoryCreatePostRepo()
        ..error = ApiError(message: 'Try again', statusCode: 422);
      final cubit = CreatePostCubit(repo: repo);
      addTearDown(cubit.close);
      cubit.setContent('My draft');
      cubit.setVisibility(PostVisibility.private);
      await cubit.submit();
      expect(cubit.state.status, CreatePostStatus.failure);
      expect(cubit.state.error!.message, 'Try again');
      expect(cubit.state.content, 'My draft');
      expect(cubit.state.visibility, PostVisibility.private);
      repo.error = null;
      await cubit.submit();
      expect(cubit.state.status, CreatePostStatus.success);
      expect(repo.requests, hasLength(2));
      expect(repo.requests.last.visibility, PostVisibility.private);
    },
  );
  test('invalid Cubit input never creates a post', () async {
    final repo = MemoryCreatePostRepo();
    final cubit = CreatePostCubit(repo: repo);
    addTearDown(cubit.close);
    await cubit.submit();
    cubit.setContent('x' * 2001);
    await cubit.submit();
    expect(cubit.state.status, CreatePostStatus.failure);
    expect(repo.requests, isEmpty);
  });
  test('late network completion does not emit after Cubit disposal', () async {
    final repo = MemoryCreatePostRepo()..gate = Completer<PostModel>();
    final cubit = CreatePostCubit(repo: repo)..setContent('Trip');
    final pending = cubit.submit();
    await cubit.close();
    repo.gate!.complete(PostModel.fromJson(postJson()));
    await pending;
  });
}
