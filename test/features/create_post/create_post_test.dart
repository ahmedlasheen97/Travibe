import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/create_post/cubit/create_post_cubit.dart';
import 'package:travibe/features/create_post/data/create_post_repo.dart';
import 'package:travibe/features/create_post/data/create_post_request.dart';
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
  test('serializes images-only posts as media_ids without content', () {
    expect(
      CreatePostRequest(
        content: '  ',
        images: [postImage('a', mediaId: 5), postImage('b', mediaId: 9)],
      ).toJson(),
      {
        'media_ids': [5, 9],
        'visibility': 'public',
      },
    );
    expect(
      CreatePostRequest(
        content: 'Trip',
        visibility: PostVisibility.followers,
        images: [postImage('a', mediaId: 5)],
      ).toJson(),
      {
        'content': 'Trip',
        'media_ids': [5],
        'visibility': 'followers',
      },
    );
  });
  test('refuses to serialize photos that have not been uploaded', () {
    expect(
      () => CreatePostRequest(content: '', images: [postImage('a')]).toJson(),
      throwsA(isA<ApiError>()),
    );
  });
  test('enforces the 10 photo app limit', () {
    final images = [for (var i = 0; i < 11; i++) postImage('$i', mediaId: i)];
    expect(
      CreatePostRequest(
        content: '',
        images: images.take(10).toList(),
      ).validationError,
      isNull,
    );
    expect(
      CreatePostRequest(content: '', images: images).validationError,
      isNotNull,
    );
  });
  test('Post is enabled by text or by a photo alone', () {
    final cubit = CreatePostCubit(repo: MemoryCreatePostRepo());
    addTearDown(cubit.close);
    expect(cubit.state.canSubmit, isFalse);
    expect(cubit.state.hasUnsavedContent, isFalse);
    cubit.setContent('   ');
    expect(cubit.state.canSubmit, isFalse);
    expect(cubit.state.hasUnsavedContent, isTrue);
    cubit.setContent('');
    cubit.addImages([postImage('a')]);
    expect(cubit.state.canSubmit, isTrue);
    expect(cubit.state.hasUnsavedContent, isTrue);
    cubit.setContent('x' * 2001);
    expect(cubit.state.canSubmit, isFalse);
  });
  test(
    'adding photos stops at the limit with a notice; removal frees slots',
    () {
      final cubit = CreatePostCubit(repo: MemoryCreatePostRepo());
      addTearDown(cubit.close);
      cubit.addImages([for (var i = 0; i < 8; i++) postImage('$i')]);
      expect(cubit.state.notice, isNull);
      expect(cubit.state.remainingImages, 2);
      cubit.addImages([postImage('x'), postImage('y'), postImage('z')]);
      expect(cubit.state.images, hasLength(10));
      expect(cubit.state.images.last.localId, 'y');
      expect(cubit.state.notice, CreatePostCubit.limitNotice);
      final id = cubit.state.noticeId;
      cubit.notifyLimit();
      expect(cubit.state.noticeId, id + 1);
      cubit.removeImage('3');
      expect(cubit.state.images.map((i) => i.localId), isNot(contains('3')));
      expect(cubit.state.remainingImages, 1);
    },
  );
  test('rejected photos produce a notice', () {
    final cubit = CreatePostCubit(repo: MemoryCreatePostRepo());
    addTearDown(cubit.close);
    cubit.addImages([postImage('a')], rejected: 2);
    expect(cubit.state.images, hasLength(1));
    expect(cubit.state.notice, CreatePostCubit.rejectedNotice);
  });
}
