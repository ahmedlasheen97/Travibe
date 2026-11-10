import 'notification_model.dart';

enum NotificationKind { comment, follow, like, messageRequest, nearby, unknown }

enum NotificationMediaKind { post, story }

/// Supplied by a verified adapter/cache, never guessed from opaque data keys.
class NotificationThumbnail {
  const NotificationThumbnail({required this.url, required this.kind});
  final String url;
  final NotificationMediaKind kind;
  bool get supported {
    final uri = Uri.tryParse(url);
    return uri != null &&
        {'https', 'http'}.contains(uri.scheme) &&
        uri.userInfo.isEmpty &&
        uri.host.isNotEmpty;
  }
}

/// Exact App\Enums\NotificationType values confirmed by the backend.
/// Fixture adapters may replace this allowlist; no fuzzy or inferred aliases.
class NotificationPresentationResolver {
  const NotificationPresentationResolver({this.verifiedTypes = laravelTypes});
  static const laravelTypes = <String, NotificationKind>{
    'post_liked': NotificationKind.like,
    'story_liked': NotificationKind.like,
    'comment_liked': NotificationKind.like,
    'post_commented': NotificationKind.comment,
    'comment_replied': NotificationKind.comment,
    'user_followed': NotificationKind.follow,
    'message_received': NotificationKind.messageRequest,
    'user_mentioned': NotificationKind.unknown,
  };
  static const _descriptions = <String, String>{
    'post_liked': 'liked your post',
    'story_liked': 'liked your story',
    'comment_liked': 'liked your comment',
    'post_commented': 'commented on your post',
    'comment_replied': 'replied to your comment',
    'user_followed': 'followed you',
    'message_received': 'sent you a message',
    'user_mentioned': 'mentioned you',
  };
  // No description/translation or preview field in opaque data is confirmed.
  String description(InboxNotification item) =>
      _descriptions[item.type] ?? 'New notification';
  final Map<String, NotificationKind> verifiedTypes;
  NotificationKind kind(InboxNotification item) =>
      verifiedTypes[item.type] ?? NotificationKind.unknown;
  NotificationThumbnail? thumbnail(InboxNotification item) => null;
  String? secondary(InboxNotification item) => null;
  static String? icon(NotificationKind kind) => switch (kind) {
    NotificationKind.comment => 'assets/images/notification/comment.svg',
    NotificationKind.follow => 'assets/images/notification/followedyou.svg',
    NotificationKind.like => 'assets/images/notification/liked.svg',
    NotificationKind.messageRequest =>
      'assets/images/notification/messagerequest.svg',
    NotificationKind.nearby =>
      'assets/images/notification/someone in yourcity.svg',
    NotificationKind.unknown => null,
  };
}
