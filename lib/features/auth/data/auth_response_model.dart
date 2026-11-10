import 'user_model.dart';

class AuthResponseModel {
  final String token;
  final String tokenType;
  final String expiresAt;
  final bool emailVerificationRequired;
  final UserModel user;

  const AuthResponseModel({
    required this.token,
    required this.tokenType,
    required this.expiresAt,
    required this.emailVerificationRequired,
    required this.user,
  });

  factory AuthResponseModel.fromJson(Map<String, dynamic> json) {
    final data = Map<String, dynamic>.from(json['data'] ?? {});

    return AuthResponseModel(
      token: data['token']?.toString() ?? '',
      tokenType: data['token_type']?.toString() ?? '',
      expiresAt: data['expires_at']?.toString() ?? '',

      emailVerificationRequired:
          data['email_verification_required'] == true ||
          data['email_verification_required'] == 'true' ||
          data['email_verification_required'] == 1 ||
          data['email_verification_required'] == '1',

      user: UserModel.fromJson(Map<String, dynamic>.from(data['user'] ?? {})),
    );
  }
}
