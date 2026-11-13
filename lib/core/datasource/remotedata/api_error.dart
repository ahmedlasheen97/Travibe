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

  @override
  String toString() => 'ApiError{message: $message}';
}
