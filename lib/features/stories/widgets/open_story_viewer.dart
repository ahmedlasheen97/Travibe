import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/utils/viewer_identity.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/stories/cubit/stories_cubit.dart';
import 'package:travibe/features/stories/cubit/story_likes_cubit.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/screens/story_viewer_screen.dart';

/// The order Home's Stories row shows and the viewer plays: my group first,
/// then everyone else in the shared source's order.
List<StoryGroup> storyPlayOrder(List<StoryGroup> groups, int? currentUserId) {
  final own = groups.where((g) => g.user.id == currentUserId).firstOrNull;
  return [?own, ...groups.where((g) => g.user.id != currentUserId)];
}

/// The one way to open someone's Stories (mine or another user's) from Home's
/// row or a profile picture: the shared [stories] source in Home's row order,
/// starting at [authorId], so swiping, "after the last story", owner controls
/// and ring refresh are identical from every entry point.
///
/// "Me" is the shared current user; [fallbackOwnerId] (Home's account, or my
/// own profile's id) is only used for the session in [fallbackSession].
///
/// When [authorId] isn't in the shared source (a profile of someone I don't
/// follow), [fallback] — their group from `GET /users/{user}/stories` — plays
/// alone and the viewer closes after its last Story. Views still go through
/// the shared source, so every ring updates.
Future<void> openStoriesOf(
  BuildContext context, {
  required int authorId,
  StoriesCubit? stories,
  StoryLikesCubit? likes,
  Object? fallbackOwnerId,
  int? fallbackSession,
  StoryGroup? fallback,
}) {
  final source = stories ?? context.read<StoriesCubit>();
  final me = int.tryParse(
    viewerUserId(
          context,
          fallbackId: fallbackOwnerId,
          fallbackSession: fallbackSession,
        ) ??
        '',
  );
  var groups = storyPlayOrder(source.state.groups, me);
  if (!groups.any((g) => g.user.id == authorId && g.stories.isNotEmpty)) {
    if (fallback == null ||
        fallback.user.id != authorId ||
        fallback.stories.isEmpty) {
      return Future.value();
    }
    groups = [fallback];
  }
  return openStoryViewer(
    context,
    groups: groups,
    authorId: authorId,
    stories: source,
    likes: likes ?? context.read<StoryLikesCubit?>(),
    currentUserId: me,
  );
}

/// Navigators with a Story viewer opened by [openStoryViewer] still up.
final _busyNavigators = Expando<bool>('openStoryViewer');

/// Opens the Story viewer (Home's row, a profile picture) and writes confirmed
/// views and deletions back to the shared [stories], so every ring updates.
Future<void> openStoryViewer(
  BuildContext context, {
  required List<StoryGroup> groups,
  required int authorId,
  required StoriesCubit stories,
  StoryLikesCubit? likes,
  int? currentUserId,
}) async {
  final session = PreferencesManager();
  final navigator = Navigator.of(context);
  if (_busyNavigators[navigator] == true || !session.hasSession) return;
  _busyNavigators[navigator] = true;
  final revision = session.sessionRevision;
  final blocks = context.read<BlockCubit?>();
  final follow = context.read<FollowCubit?>();
  bool current() => !stories.isClosed && session.sessionRevision == revision;
  var viewed = false;
  var viewerClosed = false;
  try {
    await navigator.push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StoryViewerScreen(
          groups: List.unmodifiable(groups),
          initialAuthorId: authorId,
          repo: stories.repo,
          likes: likes,
          blocks: blocks,
          follow: follow,
          currentUserId: currentUserId,
          onViewed: (id, count) {
            if (!current()) return;
            if (viewerClosed) {
              unawaited(stories.refresh());
              return;
            }
            viewed = true;
            stories.confirmedView(id, count);
          },
          onDeleted: (id) {
            if (current()) stories.confirmedDelete(id);
          },
          // The reshare is a new story of mine: refresh my ring.
          onReshared: () {
            if (current()) unawaited(stories.refresh());
          },
        ),
      ),
    );
  } finally {
    viewerClosed = true;
    _busyNavigators[navigator] = null;
    if (viewed && current()) unawaited(stories.refresh());
  }
}
