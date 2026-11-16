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

  test('upload then attach ends Done with the local preview kept', () async {
    final attached = <int>[];
    final run = cubit.start(_photo(), attach: (id) async => attached.add(id));
    expect(cubit.state, isA<ProfilePictureUploading>());
    expect(cubit.state.preview, _photo().bytes);
    var settled = false;
    unawaited(cubit.settled().then((ok) => settled = ok));
    await Future<void>.delayed(Duration.zero);
    expect(settled, false);
    upload.gates.single.complete(9);
    await run;
    await Future<void>.delayed(Duration.zero);
    expect(attached, [9]);
    expect(cubit.state, isA<ProfilePictureDone>());
    expect(cubit.state.preview, _photo().bytes);
    expect(settled, true);
    expect(upload.closed, true);
  });

  test('settled is false after a failure; discard returns to idle', () async {
    final run = cubit.start(_photo(), attach: (_) async {});
    upload.gates.single.completeError(ApiError(message: 'Offline'));
    await run;
    expect(cubit.state, isA<ProfilePictureFailed>());
    expect(await cubit.settled(), false);
    cubit.discard();
    expect(cubit.state, isA<ProfilePictureIdle>());
    expect(await cubit.settled(), true);
  });

  test(
    'a new pick cancels the one in flight; its late result is ignored',
    () async {
      final attached = <int>[];
      final first = cubit.start(
        _photo(),
        attach: (id) async => attached.add(id),
      );
      final second = cubit.start(
        _photo('b.png'),
        attach: (id) async => attached.add(id),
      );
      expect(upload.cancels.first.isCancelled, true);
      upload.gates.first.complete(1);
      upload.gates.last.complete(2);
      await Future.wait([first, second]);
      expect(attached, [2]);
      expect(cubit.state, isA<ProfilePictureDone>());
    },
  );

  test('discard is ignored while uploading', () async {
    unawaited(cubit.start(_photo(), attach: (_) async {}));
    cubit.discard();
    expect(cubit.state, isA<ProfilePictureUploading>());
  });

  test('a session change cancels and never attaches', () async {
    var attached = false;
    final run = cubit.start(_photo(), attach: (_) async => attached = true);
    await prefs.saveToken('picture-b');
    expect(cubit.state, isA<ProfilePictureIdle>());
    expect(upload.cancels.single.isCancelled, true);
    expect(await cubit.settled(), true);
    upload.gates.single.complete(3);
    await run;
    expect(attached, false);
    expect(cubit.state, isA<ProfilePictureIdle>());
  });
}
