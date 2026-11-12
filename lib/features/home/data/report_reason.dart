import 'package:travibe/core/datasource/remotedata/api_error.dart';

/// `POST /reports` reasons (`ReportReason` schema in docs/openapi.json).
enum ReportReason {
  spamOrScam('Spam or scam', 'spam_or_scam'),
  harassment('Harassment', 'harassment'),
  inappropriateContent('Inappropriate content', 'inappropriate_content'),
  somethingElse('Something else', 'something_else');

  final String label;
  final String apiValue;
  const ReportReason(this.label, this.apiValue);
}

/// What the report sheet returns. [description] is only set for
/// [ReportReason.somethingElse] and is trimmed; null when empty.
class ReportSubmission {
  const ReportSubmission(this.reason, [this.description]);
  final ReportReason reason;
  final String? description;
}

/// `description` limit from `StoreReportRequest`.
const reportDescriptionMaxLength = 1000;

/// The API answers a second pending report on the same target with a plain
/// `422`; the only signal is the message wording.
bool isAlreadyReported(ApiError error) {
  if (error.statusCode != 422) return false;
  final text = [
    error.message,
    for (final messages in error.fieldErrors.values) ...messages,
  ].join(' ').toLowerCase();
  return text.contains('already') || text.contains('pending');
}
