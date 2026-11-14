import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/stories/cubit/stories_cubit.dart';
import 'package:travibe/features/stories/cubit/story_likes_cubit.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/screens/story_viewer_screen.dart';

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
        ),
      ),
    );
  } finally {
    viewerClosed = true;
    _busyNavigators[navigator] = null;
    if (viewed && current()) unawaited(stories.refresh());
  }
}
