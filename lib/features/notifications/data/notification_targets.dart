import 'dart:async';
import 'dart:collection';
import 'package:dio/dio.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/dio_client.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/comments/data/comment_model.dart';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/data/chat_repository.dart';
import 'notification_model.dart';
import 'notification_presentation.dart';

enum NotificationTargetKind {
  post,
  story,
  comment,
  profile,
  conversation,
  buddies,

  /// My incoming follow requests list (`follow_requested`).
  followRequests,
}

/// Documented short `target_type` values; legacy morph names still accepted.
NotificationTargetKind? normalizedTargetKind(String? targetType) =>
    switch (targetType) {
      'post' || r'App\Models\Post' => NotificationTargetKind.post,
      'story' || r'App\Models\Story' => NotificationTargetKind.story,
      'comment' || r'App\Models\Comment' => NotificationTargetKind.comment,
      'user' || r'App\Models\User' => NotificationTargetKind.profile,
      'message' || r'App\Models\Message' => NotificationTargetKind.conversation,
      _ => null,
    };

class NotificationTarget {
  const NotificationTarget(this.kind, this.id, {this.postId});
  final NotificationTargetKind kind;
  final int id;
  final int? postId;
  String get key => '${kind.name}:$id:$postId';
  static int? positive(Object? value) {
    final id = int.tryParse(value?.toString() ?? '');
    return id != null && id > 0 ? id : null;
  }

  static NotificationTarget? from(InboxNotification item) {
    final id = positive(item.targetId);
    final morph = normalizedTargetKind(item.targetType);
    if (item.type == 'buddy_nearby') {
      return const NotificationTarget(NotificationTargetKind.buddies, 0);
    }
    if (item.type == 'follow_requested') {
      return const NotificationTarget(NotificationTargetKind.followRequests, 0);
    }
    if (item.type == 'user_followed' ||
        item.type == 'follow_request_accepted') {
      final actor = positive(item.actor?.id);
      return actor == null || item.actor?.isBlocked == true
          ? null
          : NotificationTarget(NotificationTargetKind.profile, actor);
    }
    if (item.type == 'message_received' ||
        item.type == 'message_request_accepted') {
      final conversation = positive(item.data['conversation_id']);
      return conversation == null
          ? null
          : NotificationTarget(
              NotificationTargetKind.conversation,
              conversation,
            );
    }
    if (id == null) return null;
    if (item.type == 'story_liked' &&
        (morph == NotificationTargetKind.story || item.targetType == null)) {
      return NotificationTarget(NotificationTargetKind.story, id);
    }
    if (item.type == 'post_liked' &&
        (morph == NotificationTargetKind.post || item.targetType == null)) {
      return NotificationTarget(NotificationTargetKind.post, id);
    }
    if (!{
      'post_commented',
      'comment_replied',
      'comment_liked',
      'user_mentioned',
    }.contains(item.type)) {
      return null;
    }
    if (morph == NotificationTargetKind.post) {
      return NotificationTarget(NotificationTargetKind.post, id);
    }
    if (morph == NotificationTargetKind.story &&
        item.type == 'user_mentioned') {
      return NotificationTarget(NotificationTargetKind.story, id);
    }
    if (morph == NotificationTargetKind.comment) {
      final post = positive(item.data['post_id']);
      return post == null
          ? null
          : NotificationTarget(
              NotificationTargetKind.comment,
              id,
              postId: post,
            );
    }
    return null;
  }
}

class NotificationContent {
  const NotificationContent(
    this.target, {
    this.post,
    this.story,
    this.comment,
    this.conversation,
    this.sessionRevision,
  });
  final NotificationTarget target;
  final PostModel? post;
  final StoryDetail? story;
  final CommentModel? comment;
  final ChatConversation? conversation;
  final int? sessionRevision;
  NotificationContent inSession(int revision) => NotificationContent(
    target,
    post: post,
    story: story,
    comment: comment,
    conversation: conversation,
    sessionRevision: revision,
  );
  NotificationThumbnail? get thumbnail {
    if (story case final story?) {
      for (final url in [story.media.thumbnailUrl, story.media.url]) {
        if (url == null) continue;
        final thumbnail = NotificationThumbnail(
          url: url,
          kind: NotificationMediaKind.story,
        );
        if (thumbnail.supported) return thumbnail;
      }
    }
    if (post case final post?) {
      for (final media in post.media) {
        if (media.mimeType?.startsWith('image/') == true) {
          for (final url in [media.thumbnailUrl, media.url]) {
            final thumbnail = NotificationThumbnail(
              url: url,
              kind: NotificationMediaKind.post,
            );
            if (thumbnail.supported) return thumbnail;
          }
        }
      }
    }
    return null;
  }
}

/// Authorized, bounded, visible-row lookups. Cache keys include the account
/// revision; neither FCM content nor guessed payload URL fields are consumed.
class NotificationTargetsRepository {
  NotificationTargetsRepository({
    Dio? dio,
    ChatRepository? chats,
    this.cacheDuration = const Duration(minutes: 2),
    this.maxConcurrent = 3,
  }) : _dio = dio ?? DioClient().dio,
       _chats = chats ?? LaravelChatRepository(dio: dio) {
    if (maxConcurrent < 1) throw ArgumentError('Invalid concurrency');
    _revision = _preferences.sessionRevision;
    _preferences.addListener(_sessionChanged);
  }
  final Dio _dio;
  final ChatRepository _chats;
  final Duration cacheDuration;
  final int maxConcurrent;
  final _preferences = PreferencesManager();
  final _cache =
      <String, (DateTime, Future<NotificationContent>, bool Function())>{};
  final _waiters = Queue<Completer<void>>();
  CancelToken _cancel = CancelToken();
  late int _revision;
  int _active = 0;
  bool _closed = false;
  void _sessionChanged() {
    if (_revision == _preferences.sessionRevision) return;
    _revision = _preferences.sessionRevision;
    invalidate();
  }

  void invalidate() {
    _cache.clear();
    _cancel.cancel();
    _cancel = CancelToken();
    _chats.cancel();
    while (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    }
  }

  bool _current(int revision) =>
      !_closed &&
      _preferences.hasSession &&
      revision == _preferences.sessionRevision;
  Future<Object?> _get(String endpoint) async {
    final revision = _revision;
    if (!_current(revision)) {
      throw ApiError(message: 'Account session changed.');
    }
    while (_active >= maxConcurrent && _current(revision)) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
    if (!_current(revision)) {
      throw ApiError(message: 'Account session changed.');
    }
    _active++;
    try {
      final cancellation = _cancel;
      final response = await _dio
          .get<Object?>(
            endpoint,
            cancelToken: cancellation,
            options: Options(
              extra: {'sessionRevision': revision},
              receiveTimeout: const Duration(seconds: 20),
            ),
          )
          .timeout(
            const Duration(seconds: 25),
            onTimeout: () {
              cancellation.cancel();
              throw TimeoutException('Content lookup timed out.');
            },
          );
      if (!_current(revision)) {
        throw ApiError(message: 'Account session changed.');
      }
      if (response.statusCode != 200) {
        throw ApiError(message: 'This content is unavailable.');
      }
      return response.data;
    } finally {
      _active--;
      if (_waiters.isNotEmpty) _waiters.removeFirst().complete();
    }
  }

  Future<NotificationContent> resolve(
    NotificationTarget target, {
    bool fresh = false,
  }) {
    final key = '$_revision:${target.key}';
    final cached = _cache[key];
    if (cached != null &&
        (!fresh || !cached.$3()) &&
        DateTime.now().isBefore(cached.$1)) {
      return cached.$2;
    }
    if (_cancel.isCancelled) _cancel = CancelToken();
    final revision = _revision;
    bool complete = false;
    final future = _resolve(target).then(
      (value) {
        complete = true;
        if (!_current(revision)) {
          throw ApiError(message: 'Account session changed.');
        }
        return value.inSession(revision);
      },
      onError: (Object error, StackTrace stack) {
        complete = true;
        Error.throwWithStackTrace(error, stack);
      },
    );
    if (_cache.length >= 128) _cache.remove(_cache.keys.first);
    // Failed targets share the same bounded TTL; pull-to-refresh or fresh taps retry.
    _cache[key] = (DateTime.now().add(cacheDuration), future, () => complete);
    return future;
  }

  Map<String, dynamic> _resource(Object? response, int id) {
    final data = response is Map ? response['data'] : null;
    if (data is! Map || data['id'] != id) {
      throw ApiError(message: 'This content is unavailable.');
    }
    return Map<String, dynamic>.from(data);
  }

  Future<NotificationContent> _resolve(NotificationTarget target) async {
    switch (target.kind) {
      case NotificationTargetKind.post:
        final json = _resource(await _get('posts/${target.id}'), target.id);
        final post = PostModel.fromJson(json);
        if (post.user.isBlocked || json['deleted_at'] != null) {
          throw ApiError(message: 'This post is unavailable.');
        }
        return NotificationContent(target, post: post);
      case NotificationTargetKind.story:
        final story = StoryDetail.fromJson(
          _resource(await _get('stories/${target.id}'), target.id),
        );
        if (story.expiresAt == null ||
            !story.expiresAt!.isAfter(DateTime.now())) {
          throw ApiError(message: 'This Story has expired.');
        }
        return NotificationContent(target, story: story);
      case NotificationTargetKind.comment:
        final comment = CommentModel.fromJson(
          _resource(
            await _get('posts/${target.postId}/comments/${target.id}'),
            target.id,
          ),
        );
        if (comment.postId != target.postId || comment.deletedAt != null) {
          throw ApiError(message: 'This comment is unavailable.');
        }
        final post = await resolve(
          NotificationTarget(NotificationTargetKind.post, target.postId!),
        );
        return NotificationContent(target, comment: comment, post: post.post);
      case NotificationTargetKind.conversation:
        final repository = _chats;
        if (repository is! ConversationDetailsRepository) {
          throw ApiError(message: 'Conversation details are unavailable.');
        }
        final conversation = await (repository as ConversationDetailsRepository)
            .conversation('${target.id}');
        if (conversation.id != '${target.id}' ||
            conversation.isBlocked != false) {
          throw ApiError(message: 'This conversation is unavailable.');
        }
        return NotificationContent(target, conversation: conversation);
      case NotificationTargetKind.profile:
      case NotificationTargetKind.buddies:
      case NotificationTargetKind.followRequests:
        return NotificationContent(target);
    }
  }

  void dispose() {
    _closed = true;
    _preferences.removeListener(_sessionChanged);
    invalidate();
  }
}
