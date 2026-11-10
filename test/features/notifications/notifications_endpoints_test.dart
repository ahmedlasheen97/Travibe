import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/core/datasource/remotedata/dio_client.dart';
import 'package:travibe/features/notifications/data/notifications_repo.dart';

class InboxAdapter implements HttpClientAdapter {
  final calls = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options);
    return ResponseBody.fromString(
      options.path == 'notifications/read-all'
          ? jsonEncode({
              'message': 'Confirmed',
              'data': {'marked_count': 3},
            })
          : options.method == 'PATCH'
          ? ''
          : jsonEncode({
              'data': {'unread_count': 3},
            }),
      options.method == 'PATCH' && options.path != 'notifications/read-all'
          ? 204
          : 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'notification endpoints retain session guard and validate read-all confirmation',
    () async {
      SharedPreferences.setMockInitialValues({'_token': 'auth'});
      final prefs = PreferencesManager();
      await prefs.init();
      final adapter = InboxAdapter(), client = DioClient();
      client.dio.httpClientAdapter = adapter;
      final repo = NotificationsRepo(apiService: ApiService(client: client));
      expect((await repo.unreadCount()).value, 3);
      await repo.markAllRead();
      await repo.markRead('notification-uuid');
      expect(adapter.calls.map((r) => '${r.method} ${r.path}'), [
        'GET notifications/unread-count',
        'PATCH notifications/read-all',
        'PATCH notifications/notification-uuid/read',
      ]);
      for (final call in adapter.calls) {
        expect(call.extra['sessionRevision'], prefs.sessionRevision);
        expect(call.headers['Authorization'], 'Bearer auth');
      }
      await prefs.clear();
    },
  );
}
