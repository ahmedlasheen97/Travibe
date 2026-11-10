import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:travibe/features/chats/data/chat_broadcast_event.dart';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/data/reverb_readiness.dart';
import 'chat_e2e_actor.dart';

/// Test-only socket, never enabled by Root. Connection/auth/subscription/event
/// delivery have distinct acknowledgements and independently fail the test.
abstract interface class ChatE2ePeer {
  Future<void> subscribe(ChatE2eHttpActor actor, String channel);
  Future<ChatMessage> message(String id);
  Future<ChatMessagesRead> readReceipt(
    String conversation,
    String reader,
    String message,
  );
  Future<void> close();
}

class ReverbTestPeer implements ChatE2ePeer {
  ReverbTestPeer._(this._socket, this._client);
  final WebSocket _socket;
  final HttpClient _client;
  late final StreamSubscription<dynamic> _subscription;
  final _connected = Completer<ReverbConnectionInfo>();
  final _events = StreamController<ChatBroadcastEvent>.broadcast();
  final _acks = <String, Completer<void>>{};
  final _subscribed = <String>{};
  final _messages = <String, ChatMessage>{};
  final _reads = <ChatMessagesRead>[];
  String? _owner;
  bool _closed = false;
  static Future<ReverbTestPeer> connect(ReverbDeployment deployment) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    ReverbTestPeer? peer;
    try {
      final socket = await WebSocket.connect(
        deployment.protocolUri.toString(),
        customClient: client,
      ).timeout(const Duration(seconds: 12));
      socket.pingInterval = const Duration(seconds: 20);
      peer = ReverbTestPeer._(socket, client);
      peer._subscription = socket.listen(
        peer._frame,
        onDone: peer._failed,
        onError: (Object _) => peer!._failed(),
      );
      await peer._connected.future.timeout(const Duration(seconds: 8));
      return peer;
    } catch (_) {
      await peer?.close();
      client.close(force: true);
      throw const ChatE2eFailure('websocket_connection_ack');
    }
  }

  void _failed() {
    if (!_connected.isCompleted) {
      _connected.completeError(
        const ChatE2eFailure('websocket_connection_ack'),
      );
    }
    for (final ack in _acks.values) {
      if (!ack.isCompleted) {
        ack.completeError(const ChatE2eFailure('subscription_closed'));
      }
    }
  }

  void _frame(dynamic raw) {
    if (_closed) return;
    try {
      final frame = jsonDecode(raw as String);
      if (frame is! Map) return;
      final event = frame['event'];
      if (event == 'pusher:connection_established') {
        if (!_connected.isCompleted) {
          _connected.complete(ReverbConnectionInfo.parse(frame));
        }
      } else if (event == 'pusher:ping') {
        _socket.add(
          jsonEncode({'event': 'pusher:pong', 'data': <String, Object?>{}}),
        );
      } else if (event == 'pusher:error' ||
          event == 'pusher:subscription_error') {
        _failed();
      } else if (event == 'pusher_internal:subscription_succeeded') {
        final channel = frame['channel'];
        final ack = _acks[channel];
        if (channel is String &&
            ack != null &&
            !ack.isCompleted &&
            reverbSubscriptionAcknowledged(frame, channel: channel)) {
          _subscribed.add(channel);
          ack.complete();
        }
      } else if (event is String && _subscribed.contains(frame['channel'])) {
        final parsed = ChatBroadcastEvent.parse(event, frame['data']);
        if (parsed == null) return;
        if (parsed is ChatMessageSent) {
          final message = parsed.message;
          _messages[message.id] = message;
          if (_messages.length > 128) _messages.remove(_messages.keys.first);
        } else if (parsed is ChatMessagesRead) {
          _reads.add(parsed);
          if (_reads.length > 32) _reads.removeAt(0);
        }
        _events.add(parsed);
      }
    } catch (_) {
      _failed();
    }
  }

  @override
  Future<void> subscribe(ChatE2eHttpActor actor, String channel) async {
    if (_closed || (_owner != null && _owner != actor.id)) {
      throw const ChatE2eFailure('socket_account_isolation');
    }
    if (_subscribed.contains(channel)) return;
    if (_acks.containsKey(channel)) {
      await _acks[channel]!.future;
      return;
    }
    _owner = actor.id;
    final connection = await _connected.future;
    final signed = await actor.authorize(connection.socketId, channel);
    if (_closed) throw const ChatE2eFailure('socket_closed');
    final ack = Completer<void>();
    _acks[channel] = ack;
    // Install the waiter before sending to avoid a fast acknowledgement race.
    final waiting = ack.future.timeout(const Duration(seconds: 10));
    _socket.add(
      jsonEncode({
        'event': 'pusher:subscribe',
        'data': {'channel': channel, ...signed},
      }),
    );
    try {
      await waiting;
    } catch (_) {
      throw const ChatE2eFailure('subscription_ack');
    }
  }

  @override
  Future<ChatMessage> message(String id) async {
    if (_messages[id] case final ChatMessage value) return value;
    try {
      final value = await _events.stream
          .firstWhere((e) => e is ChatMessageSent && e.message.id == id)
          .timeout(const Duration(seconds: 12));
      return (value as ChatMessageSent).message;
    } catch (_) {
      throw const ChatE2eFailure('message_event_delivery');
    }
  }

  @override
  Future<ChatMessagesRead> readReceipt(
    String conversation,
    String reader,
    String message,
  ) async {
    bool matches(ChatBroadcastEvent event) =>
        event is ChatMessagesRead &&
        event.conversationId == conversation &&
        event.readerId == reader &&
        (int.tryParse(event.lastReadMessageId) ?? 0) >=
            (int.tryParse(message) ?? 1);
    for (final read in _reads.reversed) {
      if (matches(read)) return read;
    }
    try {
      return await _events.stream
              .firstWhere(matches)
              .timeout(const Duration(seconds: 12))
          as ChatMessagesRead;
    } catch (_) {
      throw const ChatE2eFailure('read_event_delivery');
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _failed();
    await _subscription.cancel();
    try {
      await _socket.close().timeout(const Duration(seconds: 2));
    } catch (_) {}
    _client.close(force: true);
    await _events.close();
    _acks.clear();
    _subscribed.clear();
    _messages.clear();
    _reads.clear();
    _owner = null;
  }
}
