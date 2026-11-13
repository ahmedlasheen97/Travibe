import 'notification_model.dart';
import 'notification_targets.dart';

enum NotificationKind { comment, follow, like, messageRequest, nearby, unknown }

enum NotificationMediaKind { post, story }

/// Built from the API `preview` block or a verified adapter; never guessed.
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

/// Exact App\Enums\NotificationType values. `message_request_accepted` and
/// `buddy_nearby` are proposed backend types, rendered once they arrive.
class NotificationPresentationResolver {
  const NotificationPresentationResolver({this.verifiedTypes = laravelTypes});
  static const laravelTypes = <String, NotificationKind>{
    'post_liked': NotificationKind.like,
    'story_liked': NotificationKind.like,
    'comment_liked': NotificationKind.like,
    'post_commented': NotificationKind.comment,
    'comment_replied': NotificationKind.comment,
    'user_followed': NotificationKind.follow,
    'follow_requested': NotificationKind.follow,
    'follow_request_accepted': NotificationKind.follow,
    'message_received': NotificationKind.messageRequest,
    'message_request_accepted': NotificationKind.messageRequest,
    'buddy_nearby': NotificationKind.nearby,
    'user_mentioned': NotificationKind.unknown,
  };
  static const _descriptions = <String, String>{
    'post_liked': 'liked your post',
    'story_liked': 'liked your story',
    'comment_liked': 'liked your comment',
    'post_commented': 'commented on your post',
    'comment_replied': 'replied to your comment',
    'user_followed': 'followed you',
    'follow_requested': 'requested to follow you',
    'follow_request_accepted': 'accepted your follow request',
    'message_received': 'sent you a message',
    'message_request_accepted': 'accepted your message request',
    'buddy_nearby':
        'Someone is currently in your city. discover your new buddy.',
    'user_mentioned': 'mentioned you',
  };
  static const _excerptTypes = {
    'post_commented': 'commented',
    'comment_replied': 'replied to your comment',
    'user_mentioned': 'mentioned you',
  };

  /// Text after the bold actor name; includes the comment excerpt when known.
  String description(InboxNotification item) {
    final excerpt = item.preview?.excerpt?.trim();
    final lead = _excerptTypes[item.type];
    if (lead != null && excerpt != null && excerpt.isNotEmpty) {
      return '$lead: $excerpt';
    }
    if (item.type == 'message_received' && item.isRequest) {
      return 'sent you a message request';
    }
    final text = _descriptions[item.type] ?? 'New notification';
    final others = item.othersCount;
    if (others > 0 && item.actor != null && _descriptions[item.type] != null) {
      return 'and $others ${others == 1 ? 'other' : 'others'} $text';
    }
    return text;
  }

  final Map<String, NotificationKind> verifiedTypes;
  NotificationKind kind(InboxNotification item) =>
      verifiedTypes[item.type] ?? NotificationKind.unknown;

  NotificationThumbnail? thumbnail(InboxNotification item) {
    final url = item.preview?.thumbnailUrl;
    if (url == null) return null;
    final story =
        item.type == 'story_liked' ||
        normalizedTargetKind(item.targetType) == NotificationTargetKind.story;
    final thumbnail = NotificationThumbnail(
      url: url,
      kind: story ? NotificationMediaKind.story : NotificationMediaKind.post,
    );
    return thumbnail.supported ? thumbnail : null;
  }

  String? secondary(InboxNotification item) {
    if (item.type == 'user_followed' && item.mutualFollowers > 0) {
      final n = item.mutualFollowers;
      return '$n mutual ${n == 1 ? 'follower' : 'followers'}';
    }
    // Text-only liked post: show its excerpt under the summary (Figma).
    if (kind(item) == NotificationKind.like && thumbnail(item) == null) {
      final excerpt = item.preview?.excerpt?.trim();
      if (excerpt != null && excerpt.isNotEmpty) return excerpt;
    }
    return null;
  }

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
