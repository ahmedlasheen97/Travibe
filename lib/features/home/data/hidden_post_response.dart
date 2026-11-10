import 'package:travibe/core/datasource/remotedata/api_error.dart';

class HiddenPostResponse {
  const HiddenPostResponse({required this.isHidden, required this.message});

  final bool isHidden;
  final String message;

  factory HiddenPostResponse.fromJson(dynamic json) {
    if (json is! Map ||
        json['is_hidden'] is! bool ||
        json['message'] is! String) {
      throw ApiError(message: 'Invalid hidden post response');
    }
    return HiddenPostResponse(
      isHidden: json['is_hidden'] as bool,
      message: json['message'] as String,
    );
  }
}
