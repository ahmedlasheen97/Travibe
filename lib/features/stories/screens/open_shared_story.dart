import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/widgets/travibe_toast.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/notifications/screens/notification_navigation.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';
import 'package:travibe/features/stories/data/story_model.dart';

/// Loads one story (`GET stories/{id}`).
typedef SharedStoryLoader = Future<StoryDetail> Function(int id);

const sharedStoryUnavailable = 'Story unavailable';

/// Opens a story from a chat story-reply card: load it fresh, then show the
/// same single-story viewer notifications use. A story that is gone (403/404,
/// expired, or by a blocked author) shows [sharedStoryUnavailable] and calls
/// [onUnavailable]; other failures (offline, timeout) only show their error.
Future<void> openSharedStory(
  BuildContext context,
  int id, {
  SharedStoryLoader? load,
  StoriesRepo? stories,
  VoidCallback? onUnavailable,
}) async {
  final preferences = PreferencesManager();
  if (!preferences.hasSession || id < 1) return;
  final session = preferences.sessionRevision;
  bool stale() =>
      !preferences.hasSession || session != preferences.sessionRevision;
  void gone() {
    TravibeToast.show(
      context,
      const TravibeToastData.info(sharedStoryUnavailable),
    );
    onUnavailable?.call();
  }

  final repo = stories ?? StoriesRepo();
  StoryDetail story;
  try {
    story = await (load ?? repo.getStory)(id);
  } on ApiError catch (error) {
    if (!context.mounted || stale()) return;
    if (error.statusCode == 403 || error.statusCode == 404) {
      gone();
    } else {
      TravibeToast.show(context, TravibeToastData.error(error.message));
    }
    return;
  } catch (_) {
    if (context.mounted && !stale()) {
      TravibeToast.show(
        context,
        const TravibeToastData.error(
          'Unable to open this story. Please retry.',
        ),
      );
    }
    return;
  }
  if (!context.mounted || stale()) return;
  final blocks = context.read<BlockCubit?>();
  final expiresAt = story.expiresAt;
  if (expiresAt == null ||
      !expiresAt.isAfter(DateTime.now()) ||
      blocks?.state.isBlocked('${story.userId}') == true) {
    gone();
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      settings: RouteSettings(name: 'story/$id'),
      builder: (_) => notificationRouteScope(
        context,
        storyViewerDestination(context, story, stories: repo, blocks: blocks),
      ),
    ),
  );
}
