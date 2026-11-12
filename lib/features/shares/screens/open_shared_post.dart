import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/notifications/data/notification_targets.dart';
import 'package:travibe/features/notifications/screens/notification_navigation.dart';
import 'package:travibe/features/home/screens/post_screen.dart';

/// Loads an authorized post (`GET posts/{id}` plus block/deleted checks).
typedef SharedPostLoader = Future<NotificationContent> Function(int id);

const sharedPostUnavailable = 'This post is no longer available.';

Future<NotificationContent> _defaultLoad(int id) async {
  final resolver = NotificationTargetsRepository();
  try {
    return await resolver.resolve(
      NotificationTarget(NotificationTargetKind.post, id),
      fresh: true,
    );
  } finally {
    resolver.dispose();
  }
}

/// Opens a single post from a chat card or a `travibe://posts/{id}` link.
/// Deleted, hidden, blocked or forbidden posts show [sharedPostUnavailable].
Future<void> openSharedPost(
  BuildContext context,
  int id, {
  SharedPostLoader? load,
}) async {
  final preferences = PreferencesManager();
  if (!preferences.hasSession || id < 1) return;
  final session = preferences.sessionRevision;
  final messenger = ScaffoldMessenger.maybeOf(context);
  void unavailable() => messenger?.showSnackBar(
    const SnackBar(content: Text(sharedPostUnavailable)),
  );
  NotificationContent content;
  try {
    content = await (load ?? _defaultLoad)(id);
  } catch (_) {
    if (session == preferences.sessionRevision) unavailable();
    return;
  }
  if (!context.mounted ||
      !preferences.hasSession ||
      session != preferences.sessionRevision) {
    return;
  }
  final post = content.post;
  if (post == null ||
      context.read<BlockCubit?>()?.state.isBlocked(post.user.id) == true) {
    unavailable();
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      settings: RouteSettings(name: 'post/$id'),
      builder: (_) => notificationRouteScope(context, PostScreen(post: post)),
    ),
  );
}
