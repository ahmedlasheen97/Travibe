import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Public deployment candidate only. This does not enable app subscriptions.
class ReverbDeployment {
  ReverbDeployment({required this.base, required this.publicKey}) {
    if (base.scheme != 'wss' ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        publicKey.isEmpty ||
        !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(publicKey)) {
      throw ArgumentError('Invalid secure Reverb deployment.');
    }
  }
  final Uri base;
  final String publicKey;
  int get port => base.hasPort ? base.port : 443;
  Uri get protocolUri => base.replace(
    path: '${base.path.replaceFirst(RegExp(r'/$'), '')}/app/$publicKey',
    queryParameters: const {
      'protocol': '7',
      'client': 'flutter-travibe-readiness',
      'version': '1.0',
      'flash': 'false',
    },
  );
}

class ReverbConnectionInfo {
  const ReverbConnectionInfo(this.socketId, this.activityTimeout);
  final String socketId;
  final Duration activityTimeout;
  static ReverbConnectionInfo parse(Object? frame) {
    try {
      return _parse(frame);
    } catch (_) {
      throw const FormatException('Invalid connection acknowledgement.');
    }
  }

  static ReverbConnectionInfo _parse(Object? frame) {
    final envelope = frame is String ? jsonDecode(frame) : frame;
    if (envelope is! Map ||
        envelope['event'] != 'pusher:connection_established') {
      throw const FormatException('Connection acknowledgement missing.');
    }
    final raw = envelope['data'];
    final data = raw is String ? jsonDecode(raw) : raw;
    if (data is! Map ||
        data['socket_id'] is! String ||
        !RegExp(r'^\d+\.\d+$').hasMatch(data['socket_id'] as String) ||
        data['activity_timeout'] is! num ||
        (data['activity_timeout'] as num) <= 0) {
      throw const FormatException('Invalid connection acknowledgement.');
    }
    return ReverbConnectionInfo(
      data['socket_id'] as String,
      Duration(
        milliseconds: ((data['activity_timeout'] as num) * 1000).round(),
      ),
    );
  }

  @override
  String toString() => 'ReverbConnectionInfo(redacted)';
}

/// Bounded, anonymous probes. No credentials, subscriptions or message requests.
Future<Map<String, Object?>> probeReverb(ReverbDeployment deployment) async {
  final results = <String, Object?>{
    'host': deployment.base.host,
    'port': deployment.port,
  };
  try {
    final tls = await SecureSocket.connect(
      deployment.base.host,
      deployment.port,
      timeout: const Duration(seconds: 10),
    );
    results['tls'] = {
      'verified': true,
      'certificate_expires_utc': tls.peerCertificate?.endValidity
          .toUtc()
          .toIso8601String(),
    };
    tls.destroy();
  } catch (_) {
    results['tls'] = {'verified': false};
    return results;
  }
  for (final entry in {
    'literal': deployment.base,
    'pusher_protocol': deployment.protocolUri,
  }.entries) {
    WebSocket? socket;
    final socketClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      socket = await WebSocket.connect(
        entry.value.toString(),
      ).timeout(const Duration(seconds: 12));
      final first = await socket.first.timeout(const Duration(seconds: 8));
      final info = ReverbConnectionInfo.parse(first);
      results[entry.key] = {
        'upgrade': true,
        'connection_acknowledged': true,
        'activity_timeout_seconds': info.activityTimeout.inSeconds,
      };
    } catch (error) {
      // Do not log exception URLs, socket IDs or server payloads.
      final code = error is WebSocketException
          ? RegExp(
              r'(?:status code:|status code =)\s*(\d{3})',
            ).firstMatch(error.message)?.group(1)
          : null;
      results[entry.key] = {
        'upgrade': socket != null,
        'connection_acknowledged': false,
        'failure_type': error.runtimeType.toString(),
        if (code != null) 'http_status': int.parse(code),
      };
    } finally {
      try {
        await socket?.close().timeout(const Duration(seconds: 2));
      } catch (_) {}
      socketClient.close(force: true);
    }
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final uri = Uri.https(
      deployment.base.authority,
      '/api/v1/broadcasting/auth',
    );
    final request = await client
        .postUrl(uri)
        .timeout(const Duration(seconds: 10));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
    );
    final response = await request.close().timeout(const Duration(seconds: 10));
    results['anonymous_auth_gate'] = {
      'http_status': response.statusCode,
      'positive_authorization_verified': false,
    };
    await response.drain<void>().timeout(const Duration(seconds: 5));
  } catch (_) {
    results['anonymous_auth_gate'] = {'unavailable': true};
  } finally {
    client.close(force: true);
  }
  results['subscription_verified'] = false;
  results['message_delivery_verified'] = false;
  return results;
}

/// A signed HTTP response is not this acknowledgement. Raw wire frames, not
/// client-library aliases, must name the exact channel that was requested.
bool reverbSubscriptionAcknowledged(Object? frame, {required String channel}) {
  try {
    final envelope = frame is String ? jsonDecode(frame) : frame;
    if (envelope is! Map ||
        envelope['event'] != 'pusher_internal:subscription_succeeded' ||
        envelope['channel'] != channel) {
      return false;
    }
    final raw = envelope['data'];
    final data = raw is String ? jsonDecode(raw) : raw;
    if (data is! Map) return false;
    if (channel.startsWith('presence-conversations.')) {
      final presence = data['presence'];
      return presence is Map &&
          presence['ids'] is List &&
          presence['hash'] is Map &&
          presence['count'] is int &&
          (presence['count'] as int) >= 0;
    }
    return channel.startsWith('private-users.');
  } catch (_) {
    return false;
  }
}
