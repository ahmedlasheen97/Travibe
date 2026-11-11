import 'package:flutter/material.dart';
import 'package:travibe/core/widgets/glass_confirm_dialog.dart';
import 'package:travibe/features/home/cubit/posts_cubit.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/home/widgets/post_options_sheet.dart';

/// Same copy as the share sheet until the backend exposes post URLs.
const postLinksUnavailable = "Post links aren't available yet.";

Future<bool> showDeletePostDialog(BuildContext context) =>
    showGlassConfirmDialog(
      context,
      title: 'Delete this post?',
      message: 'This action can’t be undone.',
      confirmLabel: 'Delete',
    );

/// Runs an own-post menu action. [feed] performs the mutation; every other
/// list learns about it through the shared PostActivityCubit.
Future<void> runOwnPostAction(
  BuildContext context, {
  required PostOptionAction action,
  required PostModel post,
  required PostsCubit feed,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  void show(String text) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  switch (action) {
    case PostOptionAction.copyLink:
      show(postLinksUnavailable);
    case PostOptionAction.toggleComments:
      final disable = !post.commentsDisabled;
      final error = await feed.setCommentsDisabled(post, disable);
      show(
        error?.message ??
            (disable ? 'Commenting turned off' : 'Commenting turned on'),
      );
    case PostOptionAction.deletePost:
      if (!await showDeletePostDialog(context)) return;
      final error = await feed.deletePost(post);
      show(error?.message ?? 'Post deleted');
    default:
      return;
  }
}
