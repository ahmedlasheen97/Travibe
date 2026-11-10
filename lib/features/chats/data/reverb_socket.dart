import 'dart:async';
import 'dart:convert';
import 'package:dart_pusher_channels/dart_pusher_channels.dart';
import 'chat_repository.dart';

enum ChatSocketState { connected, disconnected, failed }

class ChatSocketFrame {
  const ChatSocketFrame(this.name, this.channel, this.data);
  final String name;
  final String? channel;
  final Object? data;
  @override
  String toString() => 'ChatSocketFrame(redacted)';
}

typedef ChatChannelSigner =
    Future<ChatChannelAuthorization> Function(String socket, String channel);

abstract interface class ReverbSocket {
  Stream<ChatSocketFrame> get frames;
  Stream<ChatSocketState> get states;
  void connect();
  void subscribe(String channel);
  void unsubscribe(String channel);
  Future<void> close();
}

/// Pure Dart/Flutter Pusher-protocol client; no Echo or native SDK integration.
class PusherReverbSocket implements ReverbSocket {
  PusherReverbSocket({required this.authorize, required this.onAuthFailure}) {
    PusherChannelsPackageLogger.disableLogs();
    _client = PusherChannelsClient.websocket(
      options: PusherChannelsOptions.custom(
        uriResolver: (_) => Uri.parse(
          'wss://travibeapp.com/reverb/app/e18855d51128bfdb7f62e5c6df983dfe?protocol=7&client=flutter-travibe&version=1.0',
        ),
      ),
      connectionErrorHandler: (_, _, _) {
        if (!_closed) _states.add(ChatSocketState.failed);
      },
      minimumReconnectDelayDuration: const Duration(seconds: 30),
    );
    _listeners.add(
      _client.eventStream.listen(
        (event) {
          if (_closed) return;
          _frames.add(
            ChatSocketFrame(event.name, event.channelName, event.data),
          );
        },
        onError: (Object _) {
          if (!_closed) _states.add(ChatSocketState.failed);
        },
      ),
    );
    _listeners.add(
      _client.onConnectionEstablished.listen((_) {
        if (_closed) return;
        _states.add(ChatSocketState.connected);
        for (final channel in _channels.values) {
          channel.subscribe();
        }
      }),
    );
    _listeners.add(
      _client.lifecycleStream.listen((state) {
        if (!_closed &&
            {
              PusherChannelsClientLifeCycleState.reconnecting,
              PusherChannelsClientLifeCycleState.disconnected,
            }.contains(state)) {
          _states.add(ChatSocketState.disconnected);
        }
      }),
    );
  }
  final ChatChannelSigner authorize;
  final void Function(int? status) onAuthFailure;
  late final PusherChannelsClient _client;
  final _frames = StreamController<ChatSocketFrame>.broadcast();
  final _states = StreamController<ChatSocketState>.broadcast();
  final _listeners = <StreamSubscription<dynamic>>[];
  final _channels = <String, Channel>{};
  bool _closed = false;
  @override
  Stream<ChatSocketFrame> get frames => _frames.stream;
  @override
  Stream<ChatSocketState> get states => _states.stream;
  Future<ChatChannelAuthorization> _sign(String socket, String channel) async {
    if (_closed) throw const FormatException('Socket closed.');
    try {
      final signed = await authorize(socket, channel);
      if (_closed) throw const FormatException('Socket closed.');
      return signed;
    } catch (error) {
      if (!_closed) {
        onAuthFailure(error is ChatAuthorizationFailure ? error.status : null);
      }
      throw const FormatException('Channel authorization unavailable.');
    }
  }

  @override
  void connect() {
    if (!_closed) {
      unawaited(
        _client.connect().catchError((Object _) {
          if (!_closed) _states.add(ChatSocketState.failed);
        }),
      );
    }
  }

  @override
  void subscribe(String name) {
    if (_closed || _channels.containsKey(name)) return;
    final Channel channel;
    if (name.startsWith('private-users.')) {
      channel = _client.privateChannel(
        name,
        authorizationDelegate: _PrivateSigner(_sign),
      );
    } else if (name.startsWith('presence-conversations.')) {
      channel = _client.presenceChannel(
        name,
        authorizationDelegate: _PresenceSigner(_sign),
      );
    } else {
      throw ArgumentError('Unsupported channel.');
    }
    _channels[name] = channel;
    if (_client.socketId != null) channel.subscribe();
  }

  @override
  void unsubscribe(String channel) {
    _channels.remove(channel)?.unsubscribe();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final sub in _listeners) {
      await sub.cancel();
    }
    for (final channel in _channels.values) {
      channel.unsubscribe();
    }
    _channels.clear();
    _client.dispose();
    await _frames.close();
    await _states.close();
  }
}

class ChatAuthorizationFailure implements Exception {
  const ChatAuthorizationFailure(this.status);
  final int? status;
  @override
  String toString() => 'ChatAuthorizationFailure(redacted)';
}

class _PrivateSigner
    extends
        EndpointAuthorizableChannelAuthorizationDelegate<
          PrivateChannelAuthorizationData
        > {
  _PrivateSigner(this.sign);
  final ChatChannelSigner sign;
  @override
  EndpointAuthFailedCallback? get onAuthFailed => null;
  @override
  Future<PrivateChannelAuthorizationData> authorizationData(
    String socketId,
    String channelName,
  ) async => PrivateChannelAuthorizationData(
    authKey: (await sign(socketId, channelName)).auth,
  );
}

class _PresenceSigner
    extends
        EndpointAuthorizableChannelAuthorizationDelegate<
          PresenceChannelAuthorizationData
        > {
  _PresenceSigner(this.sign);
  final ChatChannelSigner sign;
  @override
  EndpointAuthFailedCallback? get onAuthFailed => null;
  @override
  Future<PresenceChannelAuthorizationData> authorizationData(
    String socketId,
    String channelName,
  ) async {
    final result = await sign(socketId, channelName);
    final raw = result.channelData;
    if (raw == null) throw const FormatException('Presence data missing.');
    final parsed = jsonDecode(raw);
    if (parsed is! Map || parsed['user_id'] == null) {
      throw const FormatException('Invalid presence data.');
    }
    return PresenceChannelAuthorizationData(
      authKey: result.auth,
      channelDataEncoded: raw,
    );
  }
}
