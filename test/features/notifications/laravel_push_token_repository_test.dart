import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/dio_client.dart';
import 'package:travibe/features/notifications/data/laravel_push_token_repository.dart';
import 'package:travibe/features/notifications/data/push_device_store.dart';
import 'package:travibe/features/notifications/data/push_token_repository.dart';

class DeviceAdapter implements HttpClientAdapter {
  final calls = <Map<String, dynamic>>[];
  int postStatus = 201, deleteStatus = 204;
  bool offline = false;
  String recordId = '41';
  Completer<void>? gate;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add({
      'method': options.method,
      'path': options.path,
      'auth': options.headers['Authorization'],
      'data': options.data is Map ? Map.of(options.data as Map) : options.data,
    });
    if (gate != null) await gate!.future;
    if (offline) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'secret raw transport failure',
      );
    }
    final deleting = options.method == 'DELETE';
    final status = deleting ? deleteStatus : postStatus;
    return ResponseBody.fromString(
      status == 204
          ? ''
          : jsonEncode(
              status >= 400
                  ? {'message': 'secret raw-token echoed by server'}
                  : {
                      'data': {
                        'id': int.parse(recordId),
                        'platform': options.data['platform'],
                        'created_at': null,
                      },
                    },
            ),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final prefs = PreferencesManager();
  late DeviceAdapter adapter;
  late LaravelPushTokenRepository repo;
  late PushDeviceStore store;
  late PushAccount account;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'_token': 'bearer-a'});
    await prefs.init();
    adapter = DeviceAdapter();
    final dio = DioClient();
    dio.dio.httpClientAdapter = adapter;
    store = PushDeviceStore();
    repo = LaravelPushTokenRepository(client: dio, store: store);
    account = PushAccount(
      userId: '7',
      sessionRevision: prefs.sessionRevision,
      authorizationToken: 'bearer-a',
    );
  });
  tearDown(() => prefs.clear());
  PushRegistration registration([String platform = 'iOS']) => PushRegistration(
    account: account,
    token: 'fcm-private',
    platform: platform,
  );

  for (final platform in ['iOS', 'android']) {
    test(
      'registers $platform and parses server ID without returned raw token',
      () async {
        final record = await repo.register(registration(platform));
        expect(record.id, '41');
        expect(store.ids('7'), ['41']);
        expect(adapter.calls.single, {
          'method': 'POST',
          'path': 'device-tokens',
          'auth': 'Bearer bearer-a',
          'data': {'token': 'fcm-private', 'platform': platform.toLowerCase()},
        });
        final persisted = prefs.getString(
          PreferencesManager.pushDeviceRecordsKey,
        )!;
        expect(persisted, isNot(contains('fcm-private')));
        expect(persisted, isNot(contains('bearer-a')));
      },
    );
  }
  test(
    'idempotent POST can recover a record after session restoration',
    () async {
      final first = await repo.register(registration());
      final second = await repo.register(registration());
      expect(first.id, second.id);
      expect(store.ids('7'), ['41']);
      await prefs.init();
      expect(PushDeviceStore().ids('7'), ['41']);
    },
  );
  test(
    'DELETE uses record ID with captured auth and accepts empty 204',
    () async {
      final record = await repo.register(registration());
      await prefs.saveToken('bearer-b');
      await repo.unregister(record);
      expect(adapter.calls.last['path'], 'device-tokens/41');
      expect(adapter.calls.last['auth'], 'Bearer bearer-a');
      expect(adapter.calls.last['path'], isNot(contains('fcm-private')));
      expect(store.ids('7'), isEmpty);
    },
  );
  test('account-scoped 404 is successful cleanup', () async {
    final record = await repo.register(registration());
    adapter.deleteStatus = 404;
    await prefs.saveToken('bearer-b');
    await store.remember('8', '41');
    await repo.unregister(record);
    expect(adapter.calls.last['auth'], 'Bearer bearer-a');
    expect(store.ids('8'), ['41']);
    expect(store.ids('7'), isEmpty);
  });
  for (final status in [401, 403]) {
    test(
      '$status register and revoke preserve credentials/cleanup metadata with safe errors',
      () async {
        final record = await repo.register(registration());
        adapter.deleteStatus = status;
        await expectLater(
          repo.unregister(record),
          throwsA(
            isA<ApiError>()
                .having((e) => e.statusCode, 'status', status)
                .having(
                  (e) => e.toString(),
                  'redacted',
                  isNot(contains('secret')),
                ),
          ),
        );
        expect(store.ids('7'), ['41']);
        adapter.postStatus = status;
        await expectLater(
          repo.register(registration()),
          throwsA(
            isA<ApiError>().having((e) => e.statusCode, 'status', status),
          ),
        );
        expect(await prefs.getToken(), 'bearer-a');
      },
    );
  }
  test(
    'offline failure keeps prior IDs and maps no private transport details',
    () async {
      final record = await repo.register(registration());
      adapter.offline = true;
      await expectLater(
        repo.register(registration()),
        throwsA(
          isA<ApiError>().having(
            (e) => e.toString(),
            'safe error',
            isNot(contains('secret')),
          ),
        ),
      );
      await expectLater(repo.unregister(record), throwsA(isA<ApiError>()));
      expect(store.ids('7'), ['41']);
    },
  );
  test(
    'cleanup persists across logout and only same confirmed account retries',
    () async {
      await repo.register(registration());
      await prefs.clearSession();
      expect(store.ids('7'), ['41']);
      await prefs.saveToken('bearer-b');
      final b = PushAccount(
        userId: '8',
        sessionRevision: prefs.sessionRevision,
        authorizationToken: 'bearer-b',
      );
      await repo.cleanup(b);
      expect(adapter.calls, hasLength(1));
      await prefs.saveToken('bearer-a-new');
      final restored = PushAccount(
        userId: '7',
        sessionRevision: prefs.sessionRevision,
        authorizationToken: 'bearer-a-new',
      );
      await repo.cleanup(restored);
      expect(adapter.calls.last['auth'], 'Bearer bearer-a-new');
      expect(store.ids('7'), isEmpty);
    },
  );
  test(
    'pending request never borrows credentials from a replacement account',
    () async {
      adapter.gate = Completer();
      final request = repo.register(registration());
      await Future<void>.delayed(Duration.zero);
      await prefs.saveToken('bearer-b');
      adapter.gate!.complete();
      final record = await request;
      expect(adapter.calls.single['auth'], 'Bearer bearer-a');
      expect(record.registration.account.userId, '7');
    },
  );
  test('unsupported platform is rejected without a request', () async {
    await expectLater(
      repo.register(registration('macOS')),
      throwsA(isA<ApiError>()),
    );
    expect(adapter.calls, isEmpty);
  });
}
