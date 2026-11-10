import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/chats/screens/chat_navigation.dart';
import 'package:travibe/features/chats/screens/conversation_screen.dart';
import 'package:travibe/features/chats/data/chat_repository.dart';
import 'package:travibe/features/comments/data/comments_repo.dart';
import 'package:travibe/features/profile/data/profile_repo.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/features/home/cubit/post_activity_cubit.dart';
import 'package:travibe/features/likes/cubit/likes_cubit.dart';
import 'package:travibe/features/saved/cubit/saves_cubit.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/screens/profile_screen.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';
import 'package:travibe/features/stories/screens/story_viewer_screen.dart';
import '../data/notification_model.dart';
import '../data/notification_targets.dart';
import 'notification_post_screen.dart';

/// Borrow existing Root state across Navigator routes; never dispose its owners.
Widget notificationRouteScope(BuildContext context, Widget child) {
  final likes = context.read<LikesCubit?>();
  final saves = context.read<SavesCubit?>();
  final activity = context.read<PostActivityCubit?>();
  return chatRouteScope(
    context,
    likes == null && saves == null && activity == null
        ? child
        : MultiBlocProvider(
            providers: [
              if (likes != null) BlocProvider.value(value: likes),
              if (saves != null) BlocProvider.value(value: saves),
              if (activity != null) BlocProvider.value(value: activity),
            ],
            child: child,
          ),
  );
}

typedef NotificationDestinationOpener =
    Future<void> Function(
      BuildContext context,
      InboxNotification notification,
      NotificationContent content,
    );

Future<void> openNotificationDestination(
  BuildContext context,
  InboxNotification notification,
  NotificationContent content, {
  StoriesRepo? stories,
  ChatRepository? chats,
  CommentsRepo? comments,
  ProfileRepo? profiles,
  PostsRepo? posts,
}) async {
  final session =
      content.sessionRevision ?? PreferencesManager().sessionRevision;
  if (!PreferencesManager().hasSession ||
      session != PreferencesManager().sessionRevision) {
    throw ApiError(message: 'Account session changed.');
  }
  final target = content.target;
  final blocks = context.read<BlockCubit?>();
  final author = content.post?.user.id ?? content.story?.userId.toString();
  if (author != null && blocks?.state.isBlocked(author) == true) {
    throw ApiError(message: 'This content is unavailable.');
  }
  Widget screen;
  switch (target.kind) {
    case NotificationTargetKind.profile:
      if (blocks?.state.isBlocked('${target.id}') == true) {
        throw ApiError(message: 'This profile is unavailable.');
      }
      await ProfileScreen.open(
        context,
        userId: target.id,
        profileRepo: profiles,
        postsRepo: posts,
      );
      return;
    case NotificationTargetKind.post:
    case NotificationTargetKind.comment:
      screen = NotificationPostScreen(
        content: content,
        comments: comments,
        openComments:
            target.kind == NotificationTargetKind.comment ||
            notification.type == 'post_commented' ||
            notification.type == 'comment_replied',
      );
    case NotificationTargetKind.conversation:
      final conversation = content.conversation!;
      screen = ConversationScreen(
        conversation: conversation,
        repository: chats,
        receivedRequest: conversation.isAccepted == false,
      );
    case NotificationTargetKind.story:
      final story = content.story!;
      final group = StoryGroup.fromJson({
        'user': {
          'id': story.userId,
          'name': story.user.name,
          'avatar_url': story.user.avatarUrl,
        },
        'has_unseen': !story.hasSeen,
        'stories': [
          {
            'id': story.id,
            'thumbnail_url': story.media.thumbnailUrl,
            'created_at': story.createdAt?.toIso8601String(),
            'expires_at': story.expiresAt!.toIso8601String(),
            'views_count': story.viewsCount,
            'has_seen': story.hasSeen,
          },
        ],
      });
      screen = StoryViewerScreen(
        groups: [group],
        initialAuthorId: story.userId,
        repo: stories,
        blocks: blocks,
        follow: context.read<FollowCubit?>(),
        currentUserId: int.tryParse(
          context.read<CurrentUserCubit?>()?.state.profile?.id ?? '',
        ),
      );
  }
  if (!context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      settings: RouteSettings(
        name: 'notification-${target.kind.name}/${target.id}',
      ),
      builder: (_) => notificationRouteScope(
        context,
        _NotificationDestinationGuard(session: session, child: screen),
      ),
    ),
  );
}

class _NotificationDestinationGuard extends StatelessWidget {
  const _NotificationDestinationGuard({
    required this.session,
    required this.child,
  });
  final int session;
  final Widget child;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: PreferencesManager(),
    builder: (_, _) =>
        PreferencesManager().hasSession &&
            session == PreferencesManager().sessionRevision
        ? child
        : Scaffold(
            appBar: AppBar(leading: const BackButtonWidget()),
            body: const Center(
              child: Text('Sign in again to view this content.'),
            ),
          ),
  );
}
