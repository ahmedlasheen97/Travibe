class ApiError {
  final String message;
  final int? statusCode;
  final Map<String, List<String>> fieldErrors;

  /// The request never reached the server (offline, DNS, connect timeout).
  final bool isConnectionError;

  /// Connect/send/receive timed out; the request outcome is unknown.
  final bool isTimeout;

  ApiError({
    required this.message,
    this.statusCode,
    this.fieldErrors = const {},
    this.isConnectionError = false,
    this.isTimeout = false,
  });

  /// Shown when there is no user-facing message to show.
  static const fallbackMessage = 'Something went wrong. Please try again.';

  /// The text to show a user for [error]: the server's message for an
  /// [ApiError], otherwise [fallbackMessage]. Never exposes `toString()`.
  static String messageOf(Object? error) {
    if (error is! ApiError) return fallbackMessage;
    final text = error.message.trim();
    if (text.isEmpty || text.contains('ApiError{')) return fallbackMessage;
    return text;
  }

  /// For logs only; UI uses [message] or [messageOf].
  @override
  String toString() => 'ApiError{message: $message}';
}
