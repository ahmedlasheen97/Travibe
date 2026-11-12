class ApiError {
  final String message;
  final int? statusCode;
  final Map<String, List<String>> fieldErrors;

  /// The request never reached the server (offline, DNS, connect timeout).
  final bool isConnectionError;

  ApiError({
    required this.message,
    this.statusCode,
    this.fieldErrors = const {},
    this.isConnectionError = false,
  });

  @override
  String toString() => 'ApiError{message: $message}';
}
