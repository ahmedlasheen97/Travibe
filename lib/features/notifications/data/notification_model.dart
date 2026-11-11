import 'package:travibe/core/datasource/remotedata/api_error.dart';

class NotificationUnreadCount {
  const NotificationUnreadCount(this.value);
  final int value;
  factory NotificationUnreadCount.fromJson(dynamic json) {
    final value = json is Map && json['data'] is Map
        ? json['data']['unread_count']
        : null;
    if (value is! int || value < 0) {
      throw ApiError(
        message: 'Unable to read notification count. Please retry.',
      );
    }
    return NotificationUnreadCount(value);
  }
}

class NotificationActor {
  const NotificationActor({
    this.id,
    this.name,
    this.username,
    this.avatarUrl,
    this.isFollowing,
    this.isBlocked,
  });
  final String? id, name, username, avatarUrl;
  final bool? isFollowing, isBlocked;
  factory NotificationActor.fromJson(Map json) => NotificationActor(
    id: _id(json['id']),
    isFollowing: json['is_following'] is bool ? json['is_following'] : null,
    isBlocked: json['is_blocked'] is bool ? json['is_blocked'] : null,
    name: _text(json['name']),
    username: _text(json['username']),
    avatarUrl: _text(json['avatar_url']),
  );
}

/// Read-time `preview` block from NotificationResource (null when withheld).
class NotificationPreviewData {
  const NotificationPreviewData({this.thumbnailUrl, this.excerpt});
  final String? thumbnailUrl, excerpt;
  static NotificationPreviewData? fromJson(Object? json) {
    if (json is! Map) return null;
    final preview = NotificationPreviewData(
      thumbnailUrl: _text(json['thumbnail_url']),
      excerpt: _text(json['excerpt']),
    );
    return preview.thumbnailUrl == null && preview.excerpt == null
        ? null
        : preview;
  }
}

/// Presentation is derived exclusively from the Laravel inbox, never FCM data.
class InboxNotification {
  InboxNotification.fromJson(Map<String, dynamic> json)
    : id = json['id'].toString(),
      type = _text(json['type']) ?? 'Notification',
      targetType = _text(json['target_type']),
      targetId = json['target_id'] is int
          ? json['target_id'].toString()
          : _text(json['target_id']),
      actor = json['actor'] is Map
          ? NotificationActor.fromJson(json['actor'])
          : null,
      data = json['data'] is Map
          ? Map<String, dynamic>.from(json['data'])
          : const {},
      preview = NotificationPreviewData.fromJson(json['preview']),
      readAt = _date(json['read_at']),
      createdAt = _date(json['created_at']),
      isRead = json['read_at'] != null;
  final String id, type;
  final String? targetType, targetId;
  final NotificationActor? actor;
  final Map<String, dynamic> data;
  final NotificationPreviewData? preview;
  final DateTime? readAt, createdAt;
  final bool isRead;

  /// Proposed backend keys; absent today, so these fall back to 0/false.
  int get othersCount => _count(data['others_count']);
  int get mutualFollowers => _count(data['mutual_followers_count']);
  bool get isRequest => data['is_request'] == true;
  String get title =>
      _text(data['title']) ?? actor?.name ?? actor?.username ?? 'Notification';
  String? get description => _text(data['body']) ?? _text(data['message']);
  String get typeLabel => type.split(r'\').last.replaceAll('_', ' ');
}

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;
int _count(Object? value) => value is int && value > 0 ? value : 0;
DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

String? _id(Object? value) {
  final n = BigInt.tryParse(value?.toString() ?? '');
  return n != null && n > BigInt.zero ? n.toString() : null;
}
