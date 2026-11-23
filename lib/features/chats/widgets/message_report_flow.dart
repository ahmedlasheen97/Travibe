import 'package:flutter/material.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/widgets/travibe_toast.dart';
import 'package:travibe/features/home/widgets/report_reason_sheet.dart';
import '../data/chat_message_reports.dart';

/// Message long-press → Report: pick a reason, send `POST /reports`, then
/// confirm. Returns true when the report was accepted.
Future<bool> reportMessageFlow(
  BuildContext context, {
  required String messageId,
  required ChatMessageReports repo,
}) async {
  final submission = await ReportReasonSheet.show(context);
  if (submission == null || !context.mounted) return false;
  return _sendReport(context, messageId, repo, submission);
}

Future<bool> _sendReport(
  BuildContext context,
  String messageId,
  ChatMessageReports repo,
  ReportSubmission submission,
) async {
  final toast = TravibeToast.of(context);
  try {
    await repo.reportMessage(
      messageId,
      submission.reason,
      description: submission.description,
    );
    toast.present(
      const TravibeToastData.success("Thanks, we'll review this message"),
    );
    return true;
  } on ApiError catch (error) {
    if (isAlreadyReported(error)) {
      toast.present(
        const TravibeToastData.info(
          "You've already reported this message. We're reviewing it.",
        ),
      );
    } else if (error.statusCode == 404) {
      toast.present(
        const TravibeToastData.error('This message is no longer available.'),
      );
    } else {
      toast.present(
        TravibeToastData.error(
          error.message,
          actionLabel: 'Retry',
          onAction: () {
            if (context.mounted) {
              _sendReport(context, messageId, repo, submission);
            }
          },
        ),
      );
    }
  } on ArgumentError {
    toast.present(
      const TravibeToastData.error('This message can no longer be reported.'),
    );
  }
  return false;
}
