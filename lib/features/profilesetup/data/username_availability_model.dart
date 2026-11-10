import 'package:travibe/core/utils/json_parsers.dart';

class UsernameAvailabilityModel {
  final String username; // normalized by the server
  final bool available;

  const UsernameAvailabilityModel({
    required this.username,
    required this.available,
  });

  factory UsernameAvailabilityModel.fromJson(Map<String, dynamic> json) {
    final raw = json['data'];
    final data = raw is Map ? Map<String, dynamic>.from(raw) : json;

    return UsernameAvailabilityModel(
      username: data['username']?.toString() ?? '',
      available: parseBool(data['available']),
    );
  }
}
