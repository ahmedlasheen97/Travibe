import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'chat_broadcast_event.dart';
import 'chat_models.dart';
import 'chat_repository.dart';
import 'chat_presence_repo.dart';
import 'reverb_socket.dart';

typedef ReverbSocketFactory =
    ReverbSocket Function(
      ChatChannelSigner signer,
      void Function(int?) onAuthFailure,
    );

class ChatReverbSignal {
  const ChatReverbSignal(
    this.name,
    this.session, [
    this.event,
    this.notificationId,
  ]);
  final String name;
  final int session;
  final ChatBroadcastEvent? event;
  final String? notificationId;
}

/// One foreground connection per verified Laravel account. Socket payloads never
/// supply routes or replace the authoritative notification REST resources.
class ChatReverbService extends ChangeNotifier {
  ChatReverbService({
    ReverbSocketFactory? factory,
    LaravelChatRepository? repository,
    ChatPresenceRepo? presence,
  }) : _factory =
           factory ??
           ((sign, failed) =>
               PusherReverbSocket(authorize: sign, onAuthFailure: failed)),
       _repository = repository ?? LaravelChatRepository(),
       _presence = presence ?? ChatPresenceRepo() {
    _revision = _preferences.sessionRevision;
    _preferences.addListener(_sessionChanged);
  }
  final ReverbSocketFactory _factory;
  final LaravelChatRepository _repository;
  final ChatPresenceRepo _presence;
  final _preferences = PreferencesManager();
  final _signals = StreamController<ChatReverbSignal>.broadcast();
  Stream<ChatReverbSignal> get signals => _signals.stream;
  ReverbSocket? _socket;
  StreamSubscription<ChatSocketFrame>? _frames;
  StreamSubscription<ChatSocketState>? _states;
  Timer? _retry, _heartbeat, _typingExpiry, _connectTimeout;
  Future<void> _presenceQueue = Future.value();
  late int _revision;
  int _generation = 0, _attempt = 0;
  String? _user;
  Object? _root, _conversationOwner;
  ChatConversation? _conversation;
  Set<String> _blocked = {}, _members = {};
  bool _foreground = true, _closed = false, _typing = false;
  final Set<String> _subscribed = {}, _seen = {};
  bool get typing => _typing;
  bool memberOnline(String id) => _members.contains(id);
  String? get activeConversation => _conversation?.id;
  bool get _eligible =>
      !_closed &&
      _foreground &&
      _root != null &&
      _user != null &&
      _preferences.hasSession;
  bool get _allowedConversation {
    final c = _conversation;
    return c != null &&
        c.isBlocked == false &&
        !_blocked.contains(c.participant.id) &&
        (c.isAccepted == true || c.canSend);
  }

  void attach(Object owner) {
    _root = owner;
    _ensure();
  }

  void detach(Object owner) {
    if (!identical(_root, owner)) return;
    _root = null;
    _queuePresence(false);
    _stop();
  }

  void account(String? id) {
    if (_user == id) return;
    _stop();
    _user = id;
    _conversation = null;
    _conversationOwner = null;
    _blocked = {};
    _ensure();
  }

  void _sessionChanged() {
    if (_revision == _preferences.sessionRevision) return;
    _revision = _preferences.sessionRevision;
    _user = null;
    _conversation = null;
    _conversationOwner = null;
    _presence.cancel();
    _repository.cancel();
    _stop();
  }

  void foreground(bool value) {
    if (_foreground == value) return;
    _foreground = value;
    if (!value) {
      _queuePresence(false);
      _stop();
    } else {
      _ensure();
    }
  }

  /// Connectivity returned: skip pending backoff (and exhausted attempts) and
  /// reconnect now. A healthy subscribed socket is left untouched.
  void reconnectNow() {
    if (!_eligible || _subscribed.contains('private-users.$_user')) return;
    _stop();
    _ensure();
  }

  void blockedUsers(Set<String> ids) {
    if (setEquals(ids, _blocked)) return;
    _blocked = Set.of(ids);
    // Disconnect rather than risk a delayed authorization joining a blocked
    // channel after it was removed locally.
    _stop();
    _ensure();
  }

  void conversation(Object owner, ChatConversation? conversation) {
    if (conversation == null && !identical(owner, _conversationOwner)) return;
    final old = _allowedConversation ? _conversation?.id : null;
    _conversationOwner = conversation == null ? null : owner;
    _conversation = conversation;
    final next = _allowedConversation ? conversation?.id : null;
    if (old == next) return;
    _stop();
    _ensure();
  }

  void _ensure() {
    if (!_eligible || _socket != null || _retry != null) return;
    final generation = ++_generation, revision = _revision, user = _user!;
    bool current() =>
        !_closed &&
        _eligible &&
        generation == _generation &&
        revision == _preferences.sessionRevision &&
        user == _user;
    late ReverbSocket socket;
    socket = _factory(
      (socketId, channel) async {
        bool allowed() =>
            channel == 'private-users.$user' ||
            (_allowedConversation &&
                channel == 'presence-conversations.${_conversation!.id}');
        if (!current() || !allowed()) {
          throw const ChatAuthorizationFailure(null);
        }
        try {
          final signed = await _repository.authorizeChannel(
            socketId: socketId,
            channelName: channel,
          );
          if (!current() || !allowed()) {
            throw const ChatAuthorizationFailure(null);
          }
          return signed;
        } on ApiError catch (e) {
          throw ChatAuthorizationFailure(e.statusCode);
        }
      },
      (status) {
        if (!current()) return;
        // Auth failures must not spin, clear credentials, or bypass verification.
        if (status == 401 || status == 403) {
          _stop();
        } else {
          _reconnect();
        }
      },
    );
    _socket = socket;
    _frames = socket.frames.listen(
      (frame) {
        if (current()) _frame(frame);
      },
      onError: (Object _) {
        if (current()) _reconnect();
      },
    );
    _states = socket.states.listen((state) {
      if (!current()) return;
      if (state == ChatSocketState.connected) {
        socket.subscribe('private-users.$user');
        if (_allowedConversation) {
          socket.subscribe('presence-conversations.${_conversation!.id}');
        }
      } else {
        _reconnect();
      }
    });
    _connectTimeout = Timer(const Duration(seconds: 20), () {
      if (current() && !_subscribed.contains('private-users.$user')) {
        _reconnect();
      }
    });
    socket.connect();
    _queuePresence(true);
    _heartbeat ??= Timer.periodic(const Duration(seconds: 35), (_) {
      if (_eligible) _queuePresence(true);
    });
  }

  void _queuePresence(bool online) {
    final revision = _revision;
    if (_closed ||
        !_preferences.hasSession ||
        _user == null ||
        (online && !_eligible)) {
      return;
    }
    _presenceQueue = _presenceQueue.then((_) async {
      if (_closed ||
          revision != _preferences.sessionRevision ||
          (online && !_eligible)) {
        return;
      }
      try {
        if (online) {
          await _presence.heartbeat(revision);
        } else {
          await _presence.offline(revision);
        }
      } catch (_) {
        /* TTL covers interrupted offline requests. */
      }
    });
  }

  void _reconnect() {
    final attempt = _attempt;
    _stop(resetAttempts: false);
    if (!_eligible || attempt >= 5) return;
    _attempt = attempt + 1;
    _retry = Timer(Duration(seconds: 1 << attempt), () {
      _retry = null;
      _ensure();
    });
  }

  Map<String, dynamic>? _object(Object? data) {
    try {
      final decoded = data is String ? jsonDecode(data) : data;
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  void _frame(ChatSocketFrame frame) {
    final private = 'private-users.$_user';
    final presence = _allowedConversation
        ? 'presence-conversations.${_conversation!.id}'
        : null;
    if (frame.channel != private &&
        (presence == null || frame.channel != presence)) {
      return;
    }
    final channel = frame.channel!;
    final data = _object(frame.data);
    if (data == null) return;
    if (frame.name == 'pusher_internal:subscription_succeeded') {
      if (!_subscribed.add(channel)) return;
      if (channel == private) {
        _connectTimeout?.cancel();
        _connectTimeout = null;
        _attempt = 0;
        _signals.add(ChatReverbSignal('reconcile', _revision));
      } else {
        final p = data['presence'];
        final ids = p is Map ? p['ids'] : null;
        if (ids is List) _members = ids.map((id) => id.toString()).toSet();
        notifyListeners();
      }
      return;
    }
    if (!_subscribed.contains(channel)) return;
    // Wire protocol uses pusher_internal; prose also documents SDK aliases.
    if (channel == presence &&
        {
          'pusher_internal:member_added',
          'pusher_internal:member_removed',
          'pusher:member_added',
          'pusher:member_removed',
        }.contains(frame.name)) {
      final id = data['user_id'];
      if (id == null) return;
      if (frame.name.endsWith('member_added')) {
        _members.add(id.toString());
      } else {
        _members.remove(id.toString());
      }
      notifyListeners();
      return;
    }
    if (channel == private &&
        {
          'notification.created',
          'notification.read',
          'notifications.read_all',
          'notifications.read_conversation',
        }.contains(frame.name)) {
      final id = data['id'];
      _signals.add(
        ChatReverbSignal(
          frame.name,
          _revision,
          null,
          frame.name == 'notification.created' &&
                  id is String &&
                  id.isNotEmpty &&
                  id.length <= 128
              ? id
              : null,
        ),
      );
      return;
    }
    ChatBroadcastEvent? event;
    try {
      event = ChatBroadcastEvent.parse(frame.name, data);
    } catch (_) {
      return;
    }
    if (event == null) return;
    final cid = switch (event) {
      ChatMessageSent e => e.message.conversationId,
      ChatMessagesRead e => e.conversationId,
      ChatTypingUpdated e => e.conversationId,
    };
    if (channel == presence && cid != _conversation?.id) return;
    if (channel == private &&
        (event is! ChatMessageSent || event.message.senderId != _user)) {
      return;
    }
    if (event.key case final String key) {
      if (!_seen.add(key)) return;
      if (_seen.length > 512) _seen.remove(_seen.first);
    }
    if (event is ChatTypingUpdated &&
        event.userId == _conversation?.participant.id) {
      _typingExpiry?.cancel();
      _typing = event.isTyping;
      if (_typing) {
        _typingExpiry = Timer(const Duration(seconds: 4), () {
          _typing = false;
          if (!_closed) notifyListeners();
        });
      }
      notifyListeners();
    }
    _signals.add(ChatReverbSignal(frame.name, _revision, event));
  }

  void _stop({bool resetAttempts = true}) {
    ++_generation;
    _connectTimeout?.cancel();
    _connectTimeout = null;
    _retry?.cancel();
    _retry = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _typingExpiry?.cancel();
    _typingExpiry = null;
    unawaited(_frames?.cancel() ?? Future.value());
    _frames = null;
    unawaited(_states?.cancel() ?? Future.value());
    _states = null;
    final old = _socket;
    _socket = null;
    if (old != null) unawaited(old.close());
    _members.clear();
    _subscribed.clear();
    _seen.clear();
    _typing = false;
    if (resetAttempts) _attempt = 0;
    if (!_closed) notifyListeners();
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _preferences.removeListener(_sessionChanged);
    _presence.cancel();
    _repository.cancel();
    _stop();
    unawaited(_signals.close());
    super.dispose();
  }
}
