class ApiError {
  final String message;
  final int? statusCode;
  final Map<String, List<String>> fieldErrors;

  ApiError({
    required this.message,
    this.statusCode,
    this.fieldErrors = const {},
  });

  @override
  String toString() => 'ApiError{message: $message}';
}
