import 'package:flutter/material.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/home/cubit/hidden_posts_cubit.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/features/home/widgets/report_reason_sheet.dart';

/// Post ⋮ → Report: pick a reason, send `POST /reports`, then confirm.
/// Returns true when the report was accepted.
Future<bool> reportPostFlow(
  BuildContext context, {
  required String postId,
  required PostsRepo repo,
}) async {
  final submission = await ReportReasonSheet.show(context);
  if (submission == null || !context.mounted) return false;
  return _sendReport(context, postId, repo, submission);
}

Future<bool> _sendReport(
  BuildContext context,
  String postId,
  PostsRepo repo,
  ReportSubmission submission,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  void snack(String text, {SnackBarAction? action}) => messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), action: action));
  try {
    await repo.reportPost(
      postId,
      submission.reason,
      description: submission.description,
    );
    snack("Thanks, we'll review this post");
    return true;
  } on ApiError catch (error) {
    if (isAlreadyReported(error)) {
      snack("You've already reported this post. We're reviewing it.");
    } else {
      snack(
        error.message,
        action: SnackBarAction(
          label: 'Retry',
          onPressed: () {
            if (context.mounted) _sendReport(context, postId, repo, submission);
          },
        ),
      );
    }
  } on ArgumentError {
    snack('This post can no longer be reported.');
  }
  return false;
}

/// Post ⋮ → Not interested. There is no dedicated endpoint yet, so this
/// hides the post (`POST /posts/{post}/hide`) with its own wording.
Future<bool> notInterestedFlow(
  BuildContext context, {
  required String postId,
  required HiddenPostsCubit hidden,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final error = await hidden.setHidden(postId, true);
  if (error != null) {
    messenger?.showSnackBar(SnackBar(content: Text(error.message)));
    return false;
  }
  if (!hidden.state.hidden.contains(postId)) return false;
  messenger?.showSnackBar(
    SnackBar(
      content: const Text("Got it. We'll show you fewer posts like this."),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          final error = await hidden.setHidden(postId, false);
          if (error != null) {
            messenger.showSnackBar(SnackBar(content: Text(error.message)));
          }
        },
      ),
    ),
  );
  return true;
}
