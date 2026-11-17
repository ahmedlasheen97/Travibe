import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/media/media_upload_service.dart';
import 'package:travibe/features/profile/cubit/profile_picture_upload_cubit.dart';
import 'package:travibe/features/profile/data/profile_avatar_repo.dart';

ProfileAvatarDraft _photo([String name = 'a.png']) => ProfileAvatarDraft(
  name: name,
  bytes: base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAYAAAB/qH1jAAAAEklEQVR4nGP43+DwHxkzoAsAAHYhFfF34aTLAAAAAElFTkSuQmCC',
  ),
);

class _Upload extends MediaUploadService {
  final gates = <Completer<int>>[];
  final cancels = <CancelToken>[];
  final progress = <void Function(int, int)?>[];
  final stages = <void Function(MediaUploadStage)>[];
  bool closed = false;
  @override
  Future<int> upload({
    required String filename,
    required String contentType,
    required Uint8List bytes,
    required bool Function() isActive,
    required CancelToken cancelToken,
    required void Function(MediaUploadStage) onStage,
    void Function(int sent, int total)? onProgress,
  }) {
    cancels.add(cancelToken);
    progress.add(onProgress);
    stages.add(onStage);
    final gate = Completer<int>();
    gates.add(gate);
    return gate.future;
  }

  @override
  void close() => closed = true;
}

void main() {
  final prefs = PreferencesManager();
  late _Upload upload;
  late ProfilePictureUploadCubit cubit;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await prefs.init();
    await prefs.saveToken('picture-a');
    upload = _Upload();
    cubit = ProfilePictureUploadCubit(uploads: () => upload);
  });
  tearDown(() async {
    await cubit.close();
    await prefs.clear();
  });

  double progressOf(ProfilePictureUploadState state) =>
      (state as ProfilePictureUploading).progress;

  test('uploads only: Done carries the media ID and the preview', () async {
    final run = cubit.start(_photo());
    expect(cubit.state, isA<ProfilePictureUploading>());
    expect(cubit.state.preview, _photo().bytes);
    expect(cubit.mediaId, isNull);
    upload.gates.single.complete(9);
    await run;
    expect(cubit.state, isA<ProfilePictureDone>());
    expect(cubit.mediaId, 9);
    expect(cubit.state.preview, _photo().bytes);
    expect(upload.closed, true);
  });

  test('progress drives the ring: 0.1 → bytes → 0.85, never 0', () async {
    unawaited(cubit.start(_photo()));
    expect(progressOf(cubit.state), .1);
    upload.progress.single!(50, 100);
    expect(progressOf(cubit.state), closeTo(.475, 1e-9));
    upload.progress.single!(100, 100);
    expect(progressOf(cubit.state), closeTo(.85, 1e-9));
    upload.stages.single(MediaUploadStage.processing);
    expect(progressOf(cubit.state), .85);
    expect(pictureUploadFraction(0, 0), .1);
  });

  test('failure keeps the preview; retry re-uploads; discard idles', () async {
    final run = cubit.start(_photo());
    upload.gates.single.completeError(ApiError(message: 'Offline'));
    await run;
    expect(cubit.state, isA<ProfilePictureFailed>());
    expect(cubit.mediaId, isNull);
    final retry = cubit.retry();
    expect(cubit.state, isA<ProfilePictureUploading>());
    upload.gates.last.completeError(ApiError(message: 'Offline'));
    await retry;
    expect(upload.gates, hasLength(2));
    cubit.discard();
    expect(cubit.state, isA<ProfilePictureIdle>());
  });

  test(
    'a new pick cancels the one in flight; its late result is ignored',
    () async {
      final first = cubit.start(_photo());
      final second = cubit.start(_photo('b.png'));
      expect(upload.cancels.first.isCancelled, true);
      upload.gates.first.complete(1);
      upload.gates.last.complete(2);
      await Future.wait([first, second]);
      expect(cubit.mediaId, 2);
    },
  );

  test('discard mid-upload cancels it and ignores the result', () async {
    final run = cubit.start(_photo());
    cubit.discard();
    expect(cubit.state, isA<ProfilePictureIdle>());
    expect(upload.cancels.single.isCancelled, true);
    upload.gates.single.complete(4);
    await run;
    expect(cubit.state, isA<ProfilePictureIdle>());
  });

  test('a session change cancels the upload', () async {
    final run = cubit.start(_photo());
    await prefs.saveToken('picture-b');
    expect(cubit.state, isA<ProfilePictureIdle>());
    expect(upload.cancels.single.isCancelled, true);
    upload.gates.single.complete(3);
    await run;
    expect(cubit.state, isA<ProfilePictureIdle>());
  });
}
