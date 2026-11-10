import 'package:travibe/core/datasource/remotedata/api_error.dart';

/// Match a uniqueness failure on the structured email field, never arbitrary
/// exception text or every 422. Unknown/localized messages retain normal errors.
bool isDuplicateEmailError(ApiError error) =>
    error.statusCode == 422 &&
    (error.fieldErrors['email']?.any(
          (message) =>
              message.trim().toLowerCase() ==
              'the email has already been taken.',
        ) ??
        false);
