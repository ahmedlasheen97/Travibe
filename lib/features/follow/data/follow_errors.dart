import 'package:travibe/core/datasource/remotedata/api_error.dart';

/// Maps follow / follow-request failures to user-facing messages.
///
/// [following] is the attempted direction: true for follow, false for
/// unfollow or cancelling a request, null for follow-request accept/decline.
ApiError followError(Object error, {bool? following}) {
  if (error is! ApiError) {
    return ApiError(
      message: 'Unable to update follow status. Please try again.',
    );
  }
  final message = error.message.toLowerCase();
  final status = error.statusCode;
  String? mapped;
  if (message.contains('block')) {
    mapped = following == true
        ? "You can't follow this account."
        : 'This user is unavailable.';
  } else if (status == 409) {
    mapped = switch (following) {
      true => 'You already follow or requested this account.',
      false => 'This follow request was already handled.',
      null => 'This request was already handled.',
    };
  }
  if (mapped == null) return error;
  return ApiError(
    message: mapped,
    statusCode: status,
    fieldErrors: error.fieldErrors,
  );
}
