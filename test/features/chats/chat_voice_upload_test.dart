import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/media/media_upload_service.dart';
import 'package:travibe/core/media/media_upload_model.dart';
import 'package:travibe/features/chats/cubit/chat_audio_controller.dart';

class _MediaApi extends ApiService {
  final calls = <String>[];
  Map<String, dynamic>? presign;
  @override
  Future<dynamic> post(String path, Map<String, dynamic> data) async {
    calls.add(path);
    if (path == 'media/presign') {
      presign = data;
      return {
        'media': {'id': 19, 'status': 'pending', 'type': 'audio'},
        'upload_url': 'https://storage.invalid/recording',
        'upload_method': 'PUT',
        'upload_headers': {'Content-Type': 'audio/mp4'},
        'expires_at': '2030-01-01T00:00:00Z',
      };
    }
    return {
      'data': {
        'id': 19,
        'status': 'processing',
        'type': 'audio',
        'url': 'https://storage.invalid/recording',
        'thumbnail_url': null,
      },
    };
  }

  @override
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    calls.add(path);
    return {
      'data': {
        'id': 19,
        'status': 'ready',
        'type': 'audio',
        'url': 'https://storage.invalid/recording',
        'thumbnail_url': null,
      },
    };
  }
}

class _Storage implements HttpClientAdapter {
  RequestOptions? request;
  List<int>? uploaded;
  void Function()? onUpload;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    uploaded = await requestStream!.fold<List<int>>([], (a, b) => a..addAll(b));
    onUpload?.call();
    return ResponseBody.fromString('', 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('fixture-session');
  });
  test(
    'voice upload reuses presign PUT finalize polling and allows null thumbnail',
    () async {
      final api = _MediaApi(), storage = _Storage();
      final service = MediaUploadService(
        api: api,
        storageAdapter: storage,
        allowedContentTypes: const {'audio/mp4'},
        wait: (_) async {},
      );
      addTearDown(service.close);
      final bytes = Uint8List.fromList([1, 2, 3]);
      final id = await service.upload(
        filename: 'recording.m4a',
        contentType: 'audio/mp4',
        bytes: bytes,
        isActive: () => true,
        cancelToken: CancelToken(),
        onStage: (_) {},
      );
      expect(id, 19);
      expect(api.calls, ['media/presign', 'media/19/finalize', 'media/19']);
      expect(api.presign, {
        'filename': 'recording.m4a',
        'content_type': 'audio/mp4',
        'size': 3,
      });
      expect(storage.uploaded, bytes);
      expect(storage.request!.method, 'PUT');
      expect(
        storage.request!.headers.keys.any(
          (key) => key.toLowerCase() == 'authorization',
        ),
        false,
      );
    },
  );
  test(
    'default Profile image policy still refuses audio before network',
    () async {
      final api = _MediaApi();
      final service = MediaUploadService(api: api, storageAdapter: _Storage());
      addTearDown(service.close);
      await expectLater(
        service.upload(
          filename: 'recording.m4a',
          contentType: 'audio/mp4',
          bytes: Uint8List.fromList([1]),
          isActive: () => true,
          cancelToken: CancelToken(),
          onStage: (_) {},
        ),
        throwsA(isA<ApiError>()),
      );
      expect(api.calls, isEmpty);
    },
  );
  test('account loss after PUT prevents finalize and claiming', () async {
    final api = _MediaApi(), storage = _Storage();
    var active = true;
    storage.onUpload = () => active = false;
    final service = MediaUploadService(
      api: api,
      storageAdapter: storage,
      allowedContentTypes: const {'audio/mp4'},
    );
    addTearDown(service.close);
    await expectLater(
      service.upload(
        filename: 'recording.m4a',
        contentType: 'audio/mp4',
        bytes: Uint8List.fromList([1]),
        isActive: () => active,
        cancelToken: CancelToken(),
        onStage: (_) {},
      ),
      throwsA(isA<ApiError>()),
    );
    expect(api.calls, ['media/presign']);
  });
  test('media parser validates audio type without weakening image default', () {
    final json = {
      'data': {
        'id': 19,
        'type': 'audio',
        'status': 'ready',
        'url': 'https://storage.invalid/a',
        'thumbnail_url': null,
      },
    };
    expect(UploadMedia.fromEnvelope(json, expectedType: 'audio').id, 19);
    expect(() => UploadMedia.fromEnvelope(json), throwsFormatException);
  });
  test(
    'voice draft is cleared on account switching without creating plugins',
    () async {
      final controller = ChatAudioController();
      controller.draft = ChatVoiceDraft(Uint8List.fromList([1, 2]), 1000);
      await PreferencesManager().saveToken('replacement');
      await Future<void>.delayed(Duration.zero);
      expect(controller.draft, isNull);
      controller.dispose();
    },
  );
}
