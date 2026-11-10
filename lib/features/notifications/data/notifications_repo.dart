import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/core/models/cursor_pagination.dart';
import 'notification_model.dart';

/// Laravel remains authoritative; push data never supplies inbox records.
class NotificationsRepo {
  NotificationsRepo({ApiService? apiService})
    : _api = apiService ?? ApiService();
  final ApiService _api;
  Future<NotificationUnreadCount> unreadCount() async =>
      NotificationUnreadCount.fromJson(
        await _api.get('notifications/unread-count'),
      );
  Future<void> markAllRead() async {
    final result = await _api.patch('notifications/read-all', {});
    final count = result is Map && result['data'] is Map
        ? result['data']['marked_count']
        : null;
    if (result is! Map ||
        result['message'] is! String ||
        count is! int ||
        count < 0) {
      throw ApiError(
        message:
            'The server did not confirm notification read state. Please retry.',
      );
    }
  }

  Future<void> markRead(String id) async {
    if (id.trim().isEmpty) throw ArgumentError.value(id, 'id');
    await _api.patch('notifications/${Uri.encodeComponent(id)}/read', {});
  }

  Future<CursorPage<Map<String, dynamic>>> list({
    String? cursor,
    int perPage = 15,
  }) async {
    final response = await _api.get(
      'notifications',
      queryParameters: cursorQuery(cursor: cursor, perPage: perPage),
    );
    // Notifications omit meta.path in the confirmed cursor response. Keep the
    // shared parser strict for other feeds; supply this known endpoint locally.
    final normalized = response is Map && response['meta'] is Map
        ? {
            ...response,
            'meta': {'path': 'notifications', ...response['meta'] as Map},
          }
        : response;
    return CursorPage<Map<String, dynamic>>.fromJson(normalized, (item) {
      if (item is! Map ||
          !(item['id'] is String && (item['id'] as String).isNotEmpty ||
              item['id'] is int && (item['id'] as int) > 0)) {
        throw ApiError(message: 'Unable to read notifications. Please retry.');
      }
      return Map<String, dynamic>.unmodifiable(item);
    });
  }
}
