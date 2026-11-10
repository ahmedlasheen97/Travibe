import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:travibe/features/chats/widgets/chat_reverb_host.dart';
import 'package:travibe/features/chats/screens/conversation_screen.dart';
import 'chat_fakes.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/chats/data/chat_reverb_service.dart';
import 'package:travibe/features/chats/data/chat_repository.dart';
import 'package:travibe/features/chats/data/chat_presence_repo.dart';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/data/reverb_socket.dart';
import 'package:travibe/features/chats/cubit/chat_cubit.dart';
import 'chat_broadcast_event_test.dart' show messageEvent;

class SocketFake implements ReverbSocket {
  final input = StreamController<ChatSocketFrame>.broadcast(sync: true);
  final status = StreamController<ChatSocketState>.broadcast(sync: true);
  final subscribed = <String>[];
  bool closed = false;
  @override
  Stream<ChatSocketFrame> get frames => input.stream;
  @override
  Stream<ChatSocketState> get states => status.stream;
  @override
  void connect() => status.add(ChatSocketState.connected);
  @override
  void subscribe(String channel) => subscribed.add(channel);
  @override
  void unsubscribe(String channel) => subscribed.remove(channel);
  @override
  Future<void> close() async {
    closed = true;
  }

  void ack(String channel, {List<String> ids = const []}) => input.add(
    ChatSocketFrame('pusher_internal:subscription_succeeded', channel, {
      'presence': {'ids': ids},
    }),
  );
}

class PresenceFake extends ChatPresenceRepo {
  final calls = <String>[];
  @override
  Future<void> heartbeat(int revision) async {
    calls.add('online:$revision');
  }

  @override
  Future<void> offline(int revision) async {
    calls.add('offline:$revision');
  }
}

class AuthFake extends LaravelChatRepository {
  Completer<ChatChannelAuthorization>? gate;
  @override
  Future<ChatChannelAuthorization> authorizeChannel({
    required String socketId,
    required String channelName,
  }) async => gate == null
      ? const ChatChannelAuthorization('sanitized', null)
      : gate!.future;
}

const thread = ChatConversation(
  id: '42',
  participant: ChatParticipant(id: '7', name: 'Fixture'),
  isBlocked: false,
  isAccepted: true,
  canSend: true,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final preferences = PreferencesManager();
  late List<SocketFake> sockets;
  late List<ChatChannelSigner> signers;
  late PresenceFake presence;
  late AuthFake auth;
  late ChatReverbService service;
  late List<ChatReverbSignal> signals;
  Future<void> settle() => Future<void>.delayed(Duration.zero);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.saveToken('synthetic');
    sockets = [];
    signers = [];
    signals = [];
    presence = PresenceFake();
    auth = AuthFake();
    service = ChatReverbService(
      repository: auth,
      presence: presence,
      factory: (sign, failed) {
        signers.add(sign);
        final s = SocketFake();
        sockets.add(s);
        return s;
      },
    );
    service.signals.listen(signals.add);
    service.account('5');
  });
  tearDown(() {
    service.dispose();
  });
  test(
    'requires root attachment and verified account; ack gates events',
    () async {
      expect(sockets, isEmpty);
      service.attach('root');
      expect(sockets.single.subscribed, ['private-users.5']);
      sockets.single.input.add(
        ChatSocketFrame('message.sent', 'private-users.5', messageEvent()),
      );
      await settle();
      expect(signals, isEmpty);
      sockets.single.ack('private-users.5');
      await settle();
      expect(signals.single.name, 'reconcile');
    },
  );
  test('pending recipient and blocked conversations never subscribe', () {
    service.attach('root');
    service.conversation(
      'screen',
      const ChatConversation(
        id: '42',
        participant: ChatParticipant(id: '7', name: 'F'),
        isBlocked: false,
        isAccepted: false,
      ),
    );
    expect(sockets.single.subscribed, ['private-users.5']);
    service.conversation('screen', thread);
    expect(sockets.last.subscribed, contains('presence-conversations.42'));
    service.blockedUsers({'7'});
    expect(sockets.last.subscribed, ['private-users.5']);
  });
  test(
    'membership and typing only from acknowledged active presence channel',
    () async {
      service.attach('root');
      service.conversation('screen', thread);
      final s = sockets.last;
      s.ack('presence-conversations.42', ids: ['5', '7']);
      expect(service.memberOnline('7'), isTrue);
      s.input.add(
        const ChatSocketFrame('typing.updated', 'presence-conversations.42', {
          'conversation_id': 42,
          'user_id': 7,
          'is_typing': true,
        }),
      );
      expect(service.typing, isTrue);
      s.input.add(
        const ChatSocketFrame(
          'pusher_internal:member_removed',
          'presence-conversations.42',
          {'user_id': 7},
        ),
      );
      expect(service.memberOnline('7'), isFalse);
      service.conversation('screen', null);
      expect(service.typing, isFalse);
    },
  );
  test(
    'deduplicates private/presence message echo and ignores foreign channels',
    () async {
      service.attach('root');
      service.conversation('screen', thread);
      final s = sockets.last;
      s.ack('private-users.5');
      s.ack('presence-conversations.42');
      s.input.add(
        ChatSocketFrame('message.sent', 'private-users.5', messageEvent()),
      );
      s.input.add(
        ChatSocketFrame(
          'message.sent',
          'presence-conversations.42',
          messageEvent(),
        ),
      );
      s.input.add(
        ChatSocketFrame('message.sent', 'private-users.999', messageEvent()),
      );
      await settle();
      expect(signals.where((e) => e.name == 'message.sent'), hasLength(1));
    },
  );
  test(
    'all notification events invalidate REST; never use payload routes',
    () async {
      service.attach('root');
      final s = sockets.single;
      s.ack('private-users.5');
      for (final name in [
        'notification.created',
        'notification.read',
        'notifications.read_all',
        'notifications.read_conversation',
      ]) {
        s.input.add(
          ChatSocketFrame(name, 'private-users.5', {
            'id': 'notification-fixture-id',
            'route': '/untrusted',
          }),
        );
      }
      await settle();
      expect(signals, hasLength(5));
      expect(signals.every((s) => s.event == null), isTrue);
      expect(
        signals
            .where((s) => s.name == 'notification.created')
            .single
            .notificationId,
        'notification-fixture-id',
      );
      expect(
        signals
            .where((s) => s.name != 'notification.created')
            .every((s) => s.notificationId == null),
        isTrue,
      );
    },
  );
  test('late channel authorization rejected after account switch', () async {
    service.attach('root');
    auth.gate = Completer();
    final pending = signers.single('1.2', 'private-users.5');
    final check = expectLater(
      pending,
      throwsA(isA<ChatAuthorizationFailure>()),
    );
    await preferences.saveToken('other-synthetic');
    service.account('9');
    auth.gate!.complete(const ChatChannelAuthorization('redacted', null));
    await check;
    expect(sockets.first.closed, isTrue);
    expect(sockets.last.subscribed, ['private-users.9']);
  });
  test(
    'background serializes offline and stops connection; resume reconnects',
    () async {
      service.attach('root');
      await settle();
      service.foreground(false);
      await settle();
      expect(sockets.first.closed, isTrue);
      expect(presence.calls.last, startsWith('offline:'));
      service.foreground(true);
      await settle();
      expect(sockets, hasLength(2));
      sockets.last.ack('private-users.5');
      await settle();
      expect(signals.last.name, 'reconcile');
    },
  );
  test(
    'late REST deltas replace edits but never downgrade read receipts or resurrect deleted messages',
    () {
      final readAt = DateTime.utc(2026, 11, 8, 12);
      final seen = ChatMessage(
        id: '1',
        senderId: '5',
        kind: ChatMessageKind.text,
        text: 'new',
        updatedAt: readAt,
        readAt: readAt,
        delivery: ChatDelivery.seen,
      );
      final old = ChatMessage(
        id: '1',
        senderId: '5',
        kind: ChatMessageKind.text,
        text: 'old',
        updatedAt: readAt.subtract(const Duration(seconds: 1)),
      );
      final result = reconcileChatMessage(seen, old);
      expect(result.text, 'new');
      expect(result.delivery, ChatDelivery.seen);
      expect(result.readAt, readAt);
      final deleted = result.asDeleted();
      expect(reconcileChatMessage(deleted, seen).isDeleted, isTrue);
    },
  );
  testWidgets('bounded reconnect and logout cancel retries', (tester) async {
    service.attach('root');
    sockets.last.status.add(ChatSocketState.failed);
    await tester.pump(const Duration(seconds: 1));
    expect(sockets, hasLength(2));
    sockets.last.status.add(ChatSocketState.failed);
    await preferences.clearSession();
    await tester.pump(const Duration(seconds: 40));
    expect(sockets, hasLength(2));
  });
  testWidgets(
    'confirmed message, membership and typing update existing conversation UI',
    (tester) async {
      service.attach('root');
      final repo = FakeChatRepository()..messageItems = [];
      await tester.pumpWidget(
        ChatReverbScope(
          service: service,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, _) => MaterialApp(
              home: ConversationScreen(
                conversation: thread,
                repository: repo,
                currentUserId: '5',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final socket = sockets.last;
      socket.ack('presence-conversations.42', ids: ['5', '7']);
      socket.input.add(
        ChatSocketFrame('message.sent', 'presence-conversations.42', {
          ...messageEvent(),
          'sender_id': 7,
          'body': 'Confirmed stream fixture',
        }),
      );
      socket.input.add(
        const ChatSocketFrame('typing.updated', 'presence-conversations.42', {
          'conversation_id': 42,
          'user_id': 7,
          'is_typing': true,
        }),
      );
      await tester.pump();
      expect(find.text('Confirmed stream fixture'), findsOneWidget);
      expect(find.text('Typing…'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      service.dispose();
      await tester.pump();
    },
  );
  test(
    'HTTP snapshot cannot overwrite a later server event, including edits',
    () async {
      final response = Completer<ChatPage<ChatMessage>>();
      final list = ChatListCubit<ChatMessage>(
        fetch: (_) => response.future,
        idOf: (m) => m.id,
        cancel: () {},
        mergeRefresh: true,
      );
      final loading = list.load();
      list.appendConfirmed(
        const ChatMessage(
          id: '1',
          senderId: '7',
          kind: ChatMessageKind.text,
          text: 'updated',
        ),
        session: preferences.sessionRevision,
      );
      response.complete(
        ChatPage([
          const ChatMessage(
            id: '1',
            senderId: '7',
            kind: ChatMessageKind.text,
            text: 'old',
          ),
        ]),
      );
      await loading;
      expect(list.state.items.single.text, 'updated');
      await list.close();
    },
  );
}
