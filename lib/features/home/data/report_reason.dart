import 'package:dio/dio.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_exceptions.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';

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

/// `POST /reports` for any target [type] (`post`, `comment`, `user`, `story`,
/// `message`). Trims and caps [description]; throws [ApiError] on failure or
/// when the response doesn't confirm the report.
Future<void> submitReport(
  ApiService api, {
  required String type,
  required int id,
  required ReportReason reason,
  String? description,
}) async {
  final note = description?.trim() ?? '';
  try {
    final response = await api.post('reports', {
      'type': type,
      'id': id,
      'reason': reason.apiValue,
      if (note.isNotEmpty)
        'description': note.length > reportDescriptionMaxLength
            ? note.substring(0, reportDescriptionMaxLength)
            : note,
    });
    if (response is! Map || response['data'] is! Map) {
      throw ApiError(message: 'Unable to confirm the report. Please retry.');
    }
  } on ApiError {
    rethrow;
  } on DioException catch (e) {
    throw ApiExceptions.handleError(e);
  } catch (_) {
    throw ApiError(message: 'Unable to send the report. Please try again.');
  }
}
