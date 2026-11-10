import 'dart:async';
import 'package:dio/dio.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/dio_client.dart';

class ChatPresenceRepo {
  ChatPresenceRepo({Dio? dio}) : _dio = dio ?? DioClient().dio;
  final Dio _dio;
  CancelToken _cancel = CancelToken();
  Future<void> heartbeat(int revision) => _send(true, revision);
  Future<void> offline(int revision) => _send(false, revision);
  Future<void> _send(bool online, int revision) async {
    if (!PreferencesManager().hasSession ||
        revision != PreferencesManager().sessionRevision) {
      return;
    }
    final cancellation = _cancel;
    final response = await _dio
        .request<Object?>(
          online ? 'presence/heartbeat' : 'presence',
          cancelToken: cancellation,
          options: Options(
            method: online ? 'POST' : 'DELETE',
            sendTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
            extra: {'sessionRevision': revision},
          ),
        )
        .timeout(
          const Duration(seconds: 12),
          onTimeout: () {
            cancellation.cancel();
            if (identical(cancellation, _cancel)) _cancel = CancelToken();
            throw TimeoutException('Presence timed out.');
          },
        );
    final value = response.data;
    if (response.statusCode != 200 || value is! Map) {
      throw const FormatException('Presence unavailable.');
    }
    if (online) {
      final data = value['data'];
      if (data is! Map ||
          data['is_online'] != true ||
          data['last_seen_at'] is! String ||
          DateTime.tryParse(data['last_seen_at'] as String) == null) {
        throw const FormatException('Invalid presence response.');
      }
    } else if (value['message'] is! String) {
      throw const FormatException('Invalid offline response.');
    }
  }

  void cancel() {
    _cancel.cancel();
    _cancel = CancelToken();
  }
}
