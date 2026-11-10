import 'dart:typed_data';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:travibe/core/media/upload_diagnostics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/core/datasource/remotedata/dio_client.dart';
import 'package:travibe/core/media/media_upload_model.dart';
import 'package:travibe/core/media/media_upload_service.dart';

Map<String, dynamic> signedResponse() => {
  'expires_at': '2030-10-20T20:16:01.000000Z',
  'media': {'id': 19, 'type': 'image', 'status': 'pending'},
  'upload_headers': <String, dynamic>{
    'Host': ['travibeapp.com'],
    'Cache-Control': 'no-store',
  },
  'upload_method': 'PUT',
  'upload_url':
      'https://travibeapp.com/travibe/19/photo.png?signature=a%2Fb%2Bc&x=1&x=2',
};

class MediaApi extends ApiService {
  final calls = <String>[];
  Map<String, dynamic>? presignBody;
  Map<String, dynamic> presign = signedResponse();
  List<String> statuses = ['pending', 'processing', 'ready'];
  String finalizeStatus = 'processing';
  Object? finalizeError;
  dynamic finalizeResponse;
  String statusEnvelope = 'data';
  int? statusId;
  int get recordId => (presign['media'] as Map)['id'] as int;
  @override
  Future<dynamic> post(String endpoint, Map<String, dynamic> data) async {
    calls.add('POST $endpoint');
    if (endpoint == 'media/presign') {
      presignBody = data;
      return presign;
    }
    expect(endpoint, 'media/$recordId/finalize');
    expect(data, isEmpty);
    if (finalizeError != null) throw finalizeError!;
    return finalizeResponse ??
        {
          'data': {'id': recordId, 'status': finalizeStatus},
        };
  }

  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
    calls.add('GET $endpoint');
    expect(endpoint, 'media/$recordId');
    final status = statuses.first;
    if (statuses.length > 1) statuses.removeAt(0);
    return {
      statusEnvelope: {'id': statusId ?? recordId, 'status': status},
    };
  }
}

class StorageAdapter implements HttpClientAdapter {
  RequestOptions? request;
  List<int>? bytes;
  int status = 200;
  int requests = 0;
  bool receiveTimeout = false;
  void Function()? onRequest;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    request = options;
    bytes = await requestStream!.fold<List<int>>([], (a, b) => a..addAll(b));
    onRequest?.call();
    if (receiveTimeout) {
      throw DioException.receiveTimeout(
        timeout: options.receiveTimeout!,
        requestOptions: options,
      );
    }
    return ResponseBody.fromString('', status);
  }

  @override
  void close({bool force = false}) {}
}

class ObservedApiClient extends DioClient {
  ObservedApiClient(this.testDio);
  final Dio testDio;
  @override
  Dio get dio => testDio;
}

class JsonAdapter implements HttpClientAdapter {
  int status = 201;
  dynamic body = {
    'media': {'id': 19, 'status': 'processing'},
    'upload_url': 'https://private.invalid/?signature=SECRET',
    'secret_key_SECRET': 'SECRET',
  };
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      'content-type': ['application/json; charset=utf-8'],
    },
  );
  @override
  void close({bool force = false}) {}
}

void main() {
  Future<int> run(
    MediaUploadService service, {
    bool Function()? active,
    List<MediaUploadStage>? stages,
    CancelToken? cancel,
  }) => service.upload(
    filename: 'selected.png',
    contentType: 'image/png',
    bytes: Uint8List.fromList([1, 2, 3]),
    isActive: active ?? () => true,
    cancelToken: cancel ?? CancelToken(),
    onStage: (stage) => stages?.add(stage),
  );
  MediaUploadService service(
    MediaApi api,
    StorageAdapter storage, {
    int maxPolls = 5,
  }) {
    final result = MediaUploadService(
      api: api,
      storageAdapter: storage,
      maxPolls: maxPolls,
      now: () => DateTime.utc(2026),
      wait: (_) async {},
    );
    addTearDown(result.close);
    return result;
  }

  test(
    'immutable Uint8List raw upload removes the retained Dio MIME inference interceptor',
    () async {
      final defaultClient = Dio();
      addTearDown(() => defaultClient.close(force: true));
      defaultClient.interceptors.clear();
      expect(defaultClient.interceptors, hasLength(1));
      final adapter = StorageAdapter();
      final client = createSignedStorageClient(adapter: adapter);
      addTearDown(() => client.close(force: true));
      expect(client.interceptors, isEmpty);
      final bytes = Uint8List.fromList([137, 80, 78, 71]).asUnmodifiableView();
      expect(() => bytes[0] = 0, throwsUnsupportedError);
      await client.put<void>(
        signedResponse()['upload_url'] as String,
        data: bytes,
        options: Options(responseType: ResponseType.plain),
      );
      expect(adapter.bytes, bytes);
      expect(adapter.request!.contentType, isNull);
      expect(adapter.request!.data, same(bytes));
      expect(adapter.request!.headers.containsKey('Authorization'), false);
    },
  );

  test(
    'production pipeline handles immutable image bytes with absent or signed PNG/JPEG MIME',
    () async {
      for (final mime in ['image/png', 'image/jpeg']) {
        for (final signedType in [false, true]) {
          final api = MediaApi();
          if (signedType) {
            (api.presign['upload_headers'] as Map)['Content-Type'] = [mime];
          }
          final adapter = StorageAdapter();
          final bytes = Uint8List.fromList([1, 2, 3]).asUnmodifiableView();
          expect(
            await service(api, adapter).upload(
              filename: 'image.bin',
              contentType: mime,
              bytes: bytes,
              isActive: () => true,
              cancelToken: CancelToken(),
              onStage: (_) {},
            ),
            19,
          );
          expect(adapter.bytes, bytes);
          expect(adapter.request!.data, same(bytes));
          expect(adapter.request!.contentType, signedType ? mime : null);
          expect(adapter.request!.uri.toString(), api.presign['upload_url']);
        }
      }
    },
  );

  test(
    'conflicting signed Content-Type is rejected rather than overwritten',
    () async {
      final api = MediaApi();
      (api.presign['upload_headers'] as Map)['Content-Type'] = ['image/jpeg'];
      final adapter = StorageAdapter();
      await expectLater(run(service(api, adapter)), throwsA(isA<ApiError>()));
      expect(adapter.requests, 0);
      expect(api.calls, ['POST media/presign']);
    },
  );

  test(
    'stage diagnostics retain HTTP/category while excluding credentials and raw exception details',
    () async {
      final messages = <String>[];
      final previous = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) messages.add(message);
      };
      addTearDown(() => debugPrint = previous);
      final api = MediaApi();
      final adapter = StorageAdapter()..status = 403;
      await expectLater(run(service(api, adapter)), throwsA(isA<ApiError>()));
      expect(messages.join(), contains('stage=storage'));
      expect(messages.join(), contains('http=403'));
      logUploadFailure(
        UploadDiagnosticStage.presign,
        DioException(
          requestOptions: RequestOptions(
            path: 'https://example.invalid/?signed=SECRET',
          ),
          message: 'Bearer SECRET',
          error: 'sensitive response body',
        ),
      );
      logUploadFailure(
        UploadDiagnosticStage.finalize,
        ApiError(message: 'SECRET', statusCode: 422),
      );
      logUploadFailure(
        UploadDiagnosticStage.polling,
        const FormatException('SECRET'),
      );
      logUploadFailure(
        UploadDiagnosticStage.profilePatch,
        ApiError(message: 'SECRET', statusCode: 401),
      );
      logUploadFailure(
        UploadDiagnosticStage.profileRefresh,
        ApiError(message: 'SECRET'),
      );
      expect(messages.join(), isNot(contains('SECRET')));
      expect(messages.join(), isNot(contains('https://')));
      expect(messages.join(), isNot(contains('sensitive response body')));
      expect(messages.join(), contains('stage=finalize'));
      expect(messages.join(), contains('http=422'));
      expect(messages.join(), contains('stage=polling'));
      expect(messages.join(), contains('stage=profilePatch'));
      expect(messages.join(), contains('stage=profileRefresh'));
    },
  );

  test(
    'verified top-level presign parsing preserves strings, header arrays and integer ID',
    () {
      final json = signedResponse();
      final result = MediaPresign.fromJson(json);
      expect(result.media.id, 19);
      expect(result.media.status, MediaStatus.pending);
      expect(result.uploadUrl, json['upload_url']);
      expect(result.uploadHeaders['Host'], ['travibeapp.com']);
      expect(result.uploadHeaders['Cache-Control'], ['no-store']);
      expect(
        MediaPresign.fromJson({
          ...json,
          'upload_headers': <String, dynamic>{},
        }).uploadHeaders,
        isEmpty,
      );
      expect(result.expiresAt, DateTime.parse(json['expires_at'] as String));
      for (final bad in [
        {
          ...json,
          'media': {'id': '19', 'status': 'pending'},
        },
        {...json, 'upload_url': null},
        {...json, 'upload_method': 'POST'},
        {
          ...json,
          'upload_headers': <String, dynamic>{
            'Host': [5],
          },
        },
        {...json, 'expires_at': 'bad'},
      ]) {
        expect(() => MediaPresign.fromJson(bad), throwsFormatException);
      }
    },
  );

  test(
    'presign JSON then raw-byte PUT without Bearer, JSON or multipart; exact URL and headers',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = PreferencesManager();
      await preferences.init();
      await preferences.saveToken('test-only-media-api-token');
      addTearDown(preferences.clear);
      final api = MediaApi();
      final storage = StorageAdapter();
      final stages = <MediaUploadStage>[];
      expect(await run(service(api, storage), stages: stages), 19);
      expect(api.presignBody, {
        'filename': 'selected.png',
        'content_type': 'image/png',
        'size': 3,
      });
      expect(storage.bytes, [1, 2, 3]);
      expect(storage.request!.method, 'PUT');
      expect(storage.request!.uri.toString(), api.presign['upload_url']);
      expect(storage.request!.headers['Cache-Control'], 'no-store');
      final headers = storage.request!.headers.map(
        (k, v) => MapEntry(k.toLowerCase(), v),
      );
      expect(headers.containsKey('authorization'), false);
      expect(
        headers.containsKey('host'),
        false,
      ); // Transport derives it from the exact URL.
      expect(headers.containsKey('content-type'), false);
      expect(headers['content-length'].toString(), '3');
      expect(storage.request!.followRedirects, false);
      expect(api.calls, [
        'POST media/presign',
        'POST media/19/finalize',
        'GET media/19',
        'GET media/19',
        'GET media/19',
      ]);
      expect(stages, MediaUploadStage.values);
    },
  );

  test(
    'signed Content-Type and multivalue headers preserved without inference',
    () async {
      final api = MediaApi();
      (api.presign['upload_headers'] as Map).addAll(<String, dynamic>{
        'Content-Type': ['image/png'],
        'X-Signed': ['one', 'two'],
        'Content-Length': ['3'],
      });
      final storage = StorageAdapter();
      await run(service(api, storage));
      expect(storage.request!.contentType, 'image/png');
      expect(storage.request!.headers['X-Signed'], ['one', 'two']);
    },
  );

  test(
    'storage HTTP 200, 201 and 204 all finalize exactly once after confirmed PUT',
    () async {
      for (final status in [200, 201, 204]) {
        final api = MediaApi()..statuses = ['ready'];
        final adapter = StorageAdapter()..status = status;
        expect(await run(service(api, adapter)), 19);
        expect(adapter.requests, 1);
        expect(api.calls, [
          'POST media/presign',
          'POST media/19/finalize',
          'GET media/19',
        ]);
      }
    },
  );

  test(
    'storage receive timeout is ambiguous: pending retry checks status without new writes',
    () async {
      final api = MediaApi()..statuses = ['pending'];
      final adapter = StorageAdapter()..receiveTimeout = true;
      final uploader = service(api, adapter);
      await expectLater(
        run(uploader),
        throwsA(
          isA<ApiError>().having(
            (e) => e.message,
            'message',
            contains('uncertain'),
          ),
        ),
      );
      expect(adapter.bytes, [1, 2, 3]); // All bytes may already have arrived.
      expect(api.calls, ['POST media/presign']);
      await expectLater(run(uploader), throwsA(isA<ApiError>()));
      expect(api.calls, ['POST media/presign', 'GET media/19']);
      expect(adapter.requests, 1);
    },
  );

  test(
    'ambiguous timeout reconciles ready/processing through GET without repeating PUT or finalize',
    () async {
      for (final statuses in [
        ['ready'],
        ['processing', 'ready'],
      ]) {
        final api = MediaApi()..statuses = List.of(statuses);
        final adapter = StorageAdapter()..receiveTimeout = true;
        final uploader = service(api, adapter);
        final bytes = Uint8List.fromList([1, 2, 3]);
        Future<int> upload() => uploader.upload(
          filename: 'selected.png',
          contentType: 'image/png',
          bytes: bytes,
          isActive: () => true,
          cancelToken: CancelToken(),
          onStage: (_) {},
        );
        await expectLater(upload(), throwsA(isA<ApiError>()));
        expect(await upload(), 19);
        expect(adapter.requests, 1);
        expect(api.calls.where((e) => e.startsWith('POST')), [
          'POST media/presign',
        ]);
      }
    },
  );

  test(
    'finalize envelopes accept only known statuses and valid resource structure',
    () async {
      for (final status in ['pending', 'processing', 'ready']) {
        final api = MediaApi()
          ..finalizeStatus = status
          ..statuses = ['ready'];
        expect(await run(service(api, StorageAdapter())), 19);
      }
      for (final response in [
        {'id': 19, 'status': 'processing'},
        {
          'data': {
            'media': {'id': 19, 'status': 'processing'},
          },
        },
        {'data': null},
        {
          'data': {'id': 19, 'status': 'unknown'},
        },
        '',
      ]) {
        expect(
          () => UploadMedia.fromFinalizeEnvelope(response),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'GET supports documented data and observed media envelopes with ready and processing',
    () async {
      for (final envelope in ['data', 'media']) {
        for (final status in MediaStatus.values) {
          final parsed = UploadMedia.fromEnvelope({
            envelope: {
              'id': 19,
              'type': 'image',
              'status': status.name,
              'mime_type': 'image/png',
              'original_name': 'photo.png',
              'size': 123,
              'url': 'https://example.invalid/photo.png',
              'thumbnail_url': 'https://example.invalid/thumb.png',
              'width': status == MediaStatus.ready ? 20 : null,
              'height': status == MediaStatus.ready ? 30 : null,
              'created_at': '2026-10-21T00:00:00Z',
              'updated_at': '2026-10-21T00:00:00Z',
            },
          });
          expect(parsed.id, 19);
          expect(parsed.status, status);
        }
        final api = MediaApi()
          ..statusEnvelope = envelope
          ..statuses = ['processing', 'ready'];
        expect(await run(service(api, StorageAdapter())), 19);
      }
    },
  );

  test(
    'GET rejects invalid or conflicting wrappers and malformed inner media fields',
    () {
      final valid = {'id': 19, 'status': 'ready'};
      for (final response in [
        null,
        [],
        {},
        {'id': 19, 'status': 'ready'},
        {'data': null},
        {'media': []},
        {'data': valid, 'media': valid},
        {'data': null, 'media': valid},
        {
          'media': {'data': valid},
        },
      ]) {
        expect(() => UploadMedia.fromEnvelope(response), throwsFormatException);
      }
      for (final envelope in ['data', 'media']) {
        for (final bad in [
          {'status': 'ready'},
          {'id': 19},
          {...valid, 'id': '19'},
          {...valid, 'id': 19.0},
          {...valid, 'id': 0},
          {...valid, 'status': 'READY'},
          {...valid, 'status': null},
          {...valid, 'type': 'video'},
          {...valid, 'size': '123'},
          {...valid, 'size': -1},
          {...valid, 'url': null},
          {...valid, 'thumbnail_url': 4},
          {...valid, 'mime_type': []},
          {...valid, 'original_name': 4},
          {...valid, 'width': '20'},
          {...valid, 'height': -1},
          {...valid, 'created_at': {}},
          {...valid, 'updated_at': false},
        ]) {
          expect(
            () => UploadMedia.fromEnvelope({envelope: bad}),
            throwsFormatException,
          );
        }
      }
    },
  );

  test(
    'finalize accepts documented data and verified media processing/ready responses',
    () {
      for (final envelope in ['data', 'media']) {
        for (final status in ['processing', 'ready']) {
          expect(
            UploadMedia.fromFinalizeEnvelope({
              envelope: {'id': 19, 'type': 'image', 'status': status},
            }).status.name,
            status,
          );
        }
      }
    },
  );

  test(
    'malformed finalize response never triggers blind reupload; status can reconcile it',
    () async {
      final api = MediaApi()
        ..finalizeResponse = {'unexpected': {}}
        ..statuses = ['ready'];
      final adapter = StorageAdapter();
      final uploader = service(api, adapter);
      final bytes = Uint8List.fromList([1, 2, 3]);
      Future<int> upload() => uploader.upload(
        filename: 'selected.png',
        contentType: 'image/png',
        bytes: bytes,
        isActive: () => true,
        cancelToken: CancelToken(),
        onStage: (_) {},
      );
      await expectLater(
        upload(),
        throwsA(
          isA<ApiError>()
              .having(
                (e) => e.message,
                'message',
                contains('unexpected upload response'),
              )
              .having(
                (e) => e.message,
                'message',
                isNot(contains('uncertain')),
              ),
        ),
      );
      expect(await upload(), 19);
      expect(adapter.requests, 1);
      expect(api.calls, [
        'POST media/presign',
        'POST media/19/finalize',
        'GET media/19',
      ]);
    },
  );

  test(
    'ready media is reused for identical image bytes without presign, PUT or finalize',
    () async {
      final api = MediaApi()
        ..finalizeResponse = {
          'media': {'id': 19, 'status': 'processing'},
        }
        ..statusEnvelope = 'media'
        ..statuses = ['ready'];
      final adapter = StorageAdapter();
      final uploader = service(api, adapter);
      final first = Uint8List.fromList([1, 2, 3]).asUnmodifiableView();
      Future<int> upload(Uint8List bytes) => uploader.upload(
        filename: 'selected.png',
        contentType: 'image/png',
        bytes: bytes,
        isActive: () => true,
        cancelToken: CancelToken(),
        onStage: (_) {},
      );
      expect(await upload(first), 19);
      expect(await upload(Uint8List.fromList(first).asUnmodifiableView()), 19);
      expect(adapter.requests, 1);
      expect(api.calls, [
        'POST media/presign',
        'POST media/19/finalize',
        'GET media/19',
        'GET media/19',
      ]);
    },
  );

  test(
    'confirmed PUT with slow processing is never reported as an uncertain upload',
    () async {
      final api = MediaApi()
        ..statusEnvelope = 'media'
        ..statuses = ['processing'];
      await expectLater(
        run(service(api, StorageAdapter(), maxPolls: 2)),
        throwsA(
          isA<ApiError>()
              .having((e) => e.message, 'message', contains('processing'))
              .having(
                (e) => e.message,
                'message',
                isNot(contains('uncertain')),
              ),
        ),
      );
    },
  );

  test(
    'real API observation includes HTTP, content type, nesting/status and elapsed without secrets',
    () async {
      final messages = <String>[];
      final previous = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) messages.add(message);
      };
      addTearDown(() => debugPrint = previous);
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/'))
        ..httpClientAdapter = JsonAdapter();
      addTearDown(() => dio.close(force: true));
      final api = ApiService(
        client: ObservedApiClient(dio),
        observer: observeMediaApiRequest,
      );
      final response = await api.post('media/19/finalize', {});
      expect(response, isA<Map>());
      expect(
        messages.single,
        contains('stage=finalize http=201 type=application/json'),
      );
      expect(messages.single, contains('media:{id:integer,status:processing}'));
      expect(messages.single, contains('elapsed_ms='));
      expect(messages.single, isNot(contains('SECRET')));
      expect(messages.single, isNot(contains('https://')));
    },
  );

  test(
    'expired presign prevents storage and finalization; manual retry gets new authorization',
    () async {
      final api = MediaApi()..presign['expires_at'] = '2020-01-01T00:00:00Z';
      final storage = StorageAdapter();
      final uploader = service(api, storage);
      await expectLater(run(uploader), throwsA(isA<ApiError>()));
      expect(storage.requests, 0);
      expect(api.calls, ['POST media/presign']);
      api.presign['expires_at'] = signedResponse()['expires_at'];
      expect(await run(uploader), 19);
    },
  );

  test(
    'storage failure does not finalize and errors never expose signed URL',
    () async {
      final api = MediaApi();
      final storage = StorageAdapter()..status = 403;
      final uploader = service(api, storage);
      try {
        await run(uploader);
        fail('expected failure');
      } on ApiError catch (e) {
        expect(e.message, isNot(contains('signature')));
        expect(e.message, isNot(contains('https://')));
      }
      expect(api.calls, ['POST media/presign']);
      storage.status = 200;
      expect(await run(uploader), 19);
      expect(storage.requests, 2);
    },
  );

  test(
    'failed/unknown/mismatched status and bounded processing timeout never succeed',
    () async {
      for (final state in ['failed', 'unexpected', 'processing']) {
        final api = MediaApi()..statuses = [state];
        await expectLater(
          run(service(api, StorageAdapter(), maxPolls: 2)),
          throwsA(isA<ApiError>()),
        );
        expect(
          api.calls.where((c) => c.startsWith('GET')).length,
          lessThanOrEqualTo(2),
        );
      }
      final api = MediaApi()..statusId = 99;
      await expectLater(
        run(service(api, StorageAdapter())),
        throwsA(isA<ApiError>()),
      );
    },
  );

  test('failed finalize resource stops before status polling', () async {
    final api = MediaApi()..finalizeStatus = 'failed';
    await expectLater(
      run(service(api, StorageAdapter())),
      throwsA(isA<ApiError>()),
    );
    expect(api.calls, ['POST media/presign', 'POST media/19/finalize']);
  });

  test(
    'documented finalize 409 polls the same media without another write',
    () async {
      final api = MediaApi()
        ..finalizeError = ApiError(
          message: 'Already finalized',
          statusCode: 409,
        )
        ..statuses = ['processing', 'ready'];
      final adapter = StorageAdapter();
      expect(await run(service(api, adapter)), 19);
      expect(adapter.requests, 1);
      expect(api.calls, [
        'POST media/presign',
        'POST media/19/finalize',
        'GET media/19',
        'GET media/19',
      ]);
    },
  );

  test(
    '409 pending means processing unconfirmed; retry only reads until ready',
    () async {
      final api = MediaApi()
        ..finalizeError = ApiError(
          message: 'Already finalized',
          statusCode: 409,
        )
        ..statuses = ['pending'];
      final adapter = StorageAdapter();
      final uploader = service(api, adapter, maxPolls: 2);
      final bytes = Uint8List.fromList([1, 2, 3]);
      Future<int> upload() => uploader.upload(
        filename: 'selected.png',
        contentType: 'image/png',
        bytes: bytes,
        isActive: () => true,
        cancelToken: CancelToken(),
        onStage: (_) {},
      );
      await expectLater(
        upload(),
        throwsA(
          isA<ApiError>().having(
            (e) => e.message,
            'message',
            contains('processing'),
          ),
        ),
      );
      api.statuses = ['ready'];
      expect(await upload(), 19);
      expect(adapter.requests, 1);
      expect(api.calls.where((c) => c.startsWith('POST')), [
        'POST media/presign',
        'POST media/19/finalize',
      ]);
    },
  );

  test(
    'finalize 422 retains validation detail and permits explicit fresh upload retry',
    () async {
      final failure = ApiError(
        message: 'Uploaded object is missing',
        statusCode: 422,
        fieldErrors: {
          'media': ['Uploaded object is missing'],
        },
      );
      final api = MediaApi()..finalizeError = failure;
      final adapter = StorageAdapter();
      final uploader = service(api, adapter);
      await expectLater(run(uploader), throwsA(same(failure)));
      expect(api.calls, ['POST media/presign', 'POST media/19/finalize']);
      api.finalizeError = null;
      (api.presign['media'] as Map)['id'] = 20;
      api.statuses = ['ready'];
      expect(await run(uploader), 20);
      expect(adapter.requests, 2);
      expect(api.calls, [
        'POST media/presign',
        'POST media/19/finalize',
        'POST media/presign',
        'POST media/20/finalize',
        'GET media/20',
      ]);
    },
  );

  test(
    'Dio decodes documented HTTP 200 nested processing/ready responses and logs safe shape',
    () async {
      final messages = <String>[];
      final previous = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) messages.add(message);
      };
      addTearDown(() => debugPrint = previous);
      final adapter = JsonAdapter()..status = 200;
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/'))
        ..httpClientAdapter = adapter;
      addTearDown(() => dio.close(force: true));
      final api = ApiService(
        client: ObservedApiClient(dio),
        observer: observeMediaApiRequest,
      );
      for (final status in ['processing', 'ready']) {
        adapter.body = {
          'data': {'id': 19, 'type': 'image', 'status': status},
        };
        final json = status == 'processing'
            ? await api.post('media/19/finalize', {})
            : await api.get('media/19');
        expect(json, isA<Map>());
        expect(UploadMedia.fromEnvelope(json).status.name, status);
      }
      expect(
        messages[0],
        contains('stage=finalize http=200 type=application/json'),
      );
      expect(
        messages[0],
        contains('data:{id:integer,status:processing,type:string}'),
      );
      expect(
        messages[1],
        contains('stage=polling http=200 type=application/json'),
      );
      expect(messages[1], contains('status:ready'));
    },
  );

  test(
    'signed Host mismatch and cancellation stop subsequent requests',
    () async {
      final api = MediaApi();
      (api.presign['upload_headers'] as Map)['Host'] = ['other.invalid'];
      final storage = StorageAdapter();
      await expectLater(run(service(api, storage)), throwsA(isA<ApiError>()));
      expect(storage.requests, 0);
      var active = true;
      final nextApi = MediaApi();
      storage.onRequest = () => active = false;
      await expectLater(
        run(service(nextApi, storage), active: () => active),
        throwsA(isA<ApiError>()),
      );
      expect(nextApi.calls, ['POST media/presign']);
    },
  );
}
