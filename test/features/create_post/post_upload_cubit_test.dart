import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/create_post/cubit/post_upload_cubit.dart';
import 'package:travibe/features/create_post/data/create_post_request.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'fixtures.dart';

void main() {
  late MemoryCreatePostRepo repo;
  late FakeUploads uploads;
  late PostUploadCubit cubit;
  late List<PostUploadState> states;
  late StreamSubscription<PostUploadState> sub;
  final preferences = PreferencesManager();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    repo = MemoryCreatePostRepo();
    uploads = FakeUploads();
    cubit = PostUploadCubit(
      repo: repo,
      uploads: uploads.create,
      preferences: preferences,
    );
    states = [];
    sub = cubit.stream.listen(states.add);
  });
  tearDown(() async {
    await sub.cancel();
    await cubit.close();
    await preferences.clear();
  });

  Future<void> settle() => pumpEventQueue();

  test('uploads each photo, then creates the post with their ids', () async {
    cubit.enqueue(
      CreatePostRequest(
        content: 'Beach day',
        visibility: PostVisibility.followers,
        images: [postImage('a'), postImage('b')],
      ),
    );
    await settle();
    expect(uploads.uploaded, ['post-a.png', 'post-b.png']);
    expect(repo.requests.single.toJson(), {
      'content': 'Beach day',
      'media_ids': [100, 101],
      'visibility': 'followers',
    });
    expect(states.last, isA<PostUploadDone>());
    final progress = states
        .whereType<PostUploading>()
        .map((s) => s.progress)
        .toList();
    expect(progress.first, 0);
    expect(progress, everyElement(inInclusiveRange(0, 1)));
    for (var i = 1; i < progress.length; i++) {
      expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
    }
    expect(uploads.services.every((s) => s.closed), isTrue);
  });

  test('text-only posts skip the media pipeline', () async {
    cubit.enqueue(const CreatePostRequest(content: 'Hello'));
    await settle();
    expect(uploads.services, isEmpty);
    expect(repo.requests.single.toJson(), {
      'content': 'Hello',
      'visibility': 'public',
    });
    expect(states.last, isA<PostUploadDone>());
  });

  test('a failed photo keeps the draft; retry skips finished photos', () async {
    var created = 0;
    final failing = FakeUploads();
    final failingCubit = PostUploadCubit(
      repo: repo,
      uploads: () {
        // The second photo's first attempt fails.
        if (++created == 2) failing.failNext = 1;
        return failing.create();
      },
      preferences: preferences,
    );
    addTearDown(failingCubit.close);
    failingCubit.enqueue(
      CreatePostRequest(content: '', images: [postImage('a'), postImage('b')]),
    );
    await settle();
    final failed = failingCubit.state as PostUploadFailed;
    expect(failed.draft.images.first.mediaId, 100);
    expect(failed.draft.images.last.mediaId, isNull);
    expect(failed.message, 'Unable to upload your photo.');
    expect(repo.requests, isEmpty);

    await failingCubit.retry();
    await settle();
    expect(failing.uploaded, ['post-a.png', 'post-b.png']);
    // Photo b reuses its own service so its recovery state survives.
    expect(failing.services, hasLength(2));
    expect(repo.requests.single.toJson()['media_ids'], [100, 101]);
    expect(failingCubit.state, isA<PostUploadDone>());
  });

  test(
    'a failed post request keeps uploaded ids and retries only the post',
    () async {
      repo.error = ApiError(message: 'Server error', statusCode: 500);
      cubit.enqueue(CreatePostRequest(content: 'x', images: [postImage('a')]));
      await settle();
      final failed = cubit.state as PostUploadFailed;
      expect(failed.message, 'Server error');
      expect(failed.draft.content, 'x');
      expect(failed.draft.images.single.mediaId, 100);
      repo.error = null;
      await cubit.retry();
      await settle();
      expect(uploads.uploaded, hasLength(1));
      expect(repo.requests, hasLength(2));
      expect(cubit.state, isA<PostUploadDone>());
    },
  );

  test('discard drops the failed draft and continues the queue', () async {
    repo.error = ApiError(message: 'Nope');
    cubit.enqueue(const CreatePostRequest(content: 'first'));
    await settle();
    expect(cubit.state, isA<PostUploadFailed>());
    repo.error = null;
    cubit.enqueue(const CreatePostRequest(content: 'second'));
    await settle();
    // The failure blocks the queue until the user decides.
    expect(cubit.state, isA<PostUploadFailed>());
    expect((cubit.state as PostUploadFailed).queued, 0);
    expect(cubit.pending, 1);
    cubit.discard();
    await settle();
    expect(repo.requests.last.content, 'second');
    expect(cubit.state, isA<PostUploadDone>());
  });

  test('drafts publish one at a time in order', () async {
    repo.gate = Completer<PostModel>();
    cubit.enqueue(const CreatePostRequest(content: 'one'));
    cubit.enqueue(const CreatePostRequest(content: 'two'));
    await settle();
    expect(repo.requests.map((r) => r.content), ['one']);
    expect((cubit.state as PostUploading).queued, 1);
    final gate = repo.gate!;
    repo.gate = null;
    gate.complete(PostModel.fromJson(postJson(content: 'one')));
    await settle();
    expect(repo.requests.map((r) => r.content), ['one', 'two']);
    expect(states.whereType<PostUploadDone>(), hasLength(2));
  });

  test('a session change cancels the upload and never posts', () async {
    uploads.gate = Completer<void>();
    cubit.enqueue(CreatePostRequest(content: 'mine', images: [postImage('a')]));
    await settle();
    expect(cubit.state, isA<PostUploading>());
    await preferences.saveToken('another-account');
    expect(cubit.state, isA<PostUploadIdle>());
    uploads.gate!.complete();
    await settle();
    expect(repo.requests, isEmpty);
    expect(cubit.state, isA<PostUploadIdle>());
    expect(uploads.services.single.closed, isTrue);
  });

  test('invalid drafts are ignored', () async {
    cubit.enqueue(const CreatePostRequest(content: ' '));
    await settle();
    expect(states, isEmpty);
  });
}
