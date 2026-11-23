import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/home/data/report_reason.dart';

/// `POST /reports` with `type: message`. Goes through [ApiService] rather than
/// the chat repository so the server's 422 wording reaches
/// [isAlreadyReported]. A missing, unsent or hidden message is a 404; your
/// own message is a 422.
class ChatMessageReports {
  ChatMessageReports({ApiService? apiService})
    : _apiService = apiService ?? ApiService();
  final ApiService _apiService;

  Future<void> reportMessage(
    String messageId,
    ReportReason reason, {
    String? description,
  }) async {
    final id = int.tryParse(messageId);
    if (id == null || id < 1) throw ArgumentError.value(messageId, 'messageId');
    await submitReport(
      _apiService,
      type: 'message',
      id: id,
      reason: reason,
      description: description,
    );
  }
}
