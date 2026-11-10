/// Immutable credentials for the confirmed Laravel principal. The HTTP
/// adapter MUST use these credentials, never the mutable current user's token.
class PushAccount {
  const PushAccount({
    required this.userId,
    required this.sessionRevision,
    required this.authorizationToken,
  });
  final String userId, authorizationToken;
  final int sessionRevision;

  @override
  bool operator ==(Object other) =>
      other is PushAccount &&
      other.userId == userId &&
      other.sessionRevision == sessionRevision &&
      other.authorizationToken == authorizationToken;
  @override
  int get hashCode => Object.hash(userId, sessionRevision, authorizationToken);
  @override
  String toString() => 'PushAccount(redacted)';
}

class PushRegistration {
  const PushRegistration({
    required this.account,
    required this.token,
    required this.platform,
  });
  final PushAccount account;
  final String token, platform;
  @override
  String toString() => 'PushRegistration(redacted)';
}

class PushDeviceRecord {
  const PushDeviceRecord({required this.id, required this.registration});
  final String id;
  final PushRegistration registration;
  @override
  String toString() => 'PushDeviceRecord(redacted)';
}

/// Confirmed Laravel device-token contract. Mutations are idempotent.
abstract interface class PushTokenRepository {
  bool get supported;
  Future<PushDeviceRecord> register(PushRegistration registration);
  Future<void> unregister(PushDeviceRecord record);
  Future<void> cleanup(PushAccount account, {String? exceptId});
}

class UnavailablePushTokenRepository implements PushTokenRepository {
  const UnavailablePushTokenRepository();
  @override
  bool get supported => false;
  @override
  Future<void> cleanup(PushAccount account, {String? exceptId}) async {}
  @override
  Future<PushDeviceRecord> register(PushRegistration registration) =>
      Future.error(UnsupportedError('No verified push registration API.'));
  @override
  Future<void> unregister(PushDeviceRecord record) =>
      Future.error(UnsupportedError('No verified push revocation API.'));
}
