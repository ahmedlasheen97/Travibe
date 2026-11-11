import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/chats/cubit/chat_cubit.dart';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/data/chat_realtime.dart';
import 'package:travibe/features/chats/data/chat_repository.dart';
import 'chat_fakes.dart';

void main() {
  final preferences = PreferencesManager();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.saveToken('test-session');
  });
  ChatListCubit<ChatConversation> list(FakeChatRepository repo) =>
      ChatListCubit(
        fetch: (next) => repo.conversations(continuation: next),
        idOf: (item) => item.id,
        cancel: repo.cancel,
      );
  test(
    'production without a confirmed schema refuses network operations',
    () async {
      final repo = LaravelChatRepository(contract: null);
      expect(repo.capabilities.sendText, false);
      await expectLater(repo.conversations(), throwsA(isA<ChatUnavailable>()));
      await expectLater(
        repo.sendText('1', 'Hello'),
        throwsA(isA<ChatUnavailable>()),
      );
      await expectLater(repo.create('1'), throwsA(isA<ChatUnavailable>()));
      await expectLater(repo.markRead('1'), throwsA(isA<ChatUnavailable>()));
      await expectLater(
        repo.resolveRequest('1', accept: true),
        throwsA(isA<ChatUnavailable>()),
      );
    },
  );
  test('inbox coalesces duplicate loads', () async {
    final repo = FakeChatRepository()..loading = Completer();
    final cubit = list(repo);
    final a = cubit.load(), b = cubit.load();
    expect(repo.loads, 1);
    repo.loading!.complete(ChatPage([conversation]));
    await Future.wait([a, b]);
    expect(cubit.state.items.length, 1);
    await cubit.close();
  });
  test('late old-account inbox response is ignored', () async {
    final repo = FakeChatRepository()..loading = Completer();
    final cubit = list(repo);
    final pending = cubit.load();
    await preferences.saveToken('different-account');
    repo.loading!.complete(ChatPage([conversation]));
    await pending;
    expect(cubit.state.items, isEmpty);
    expect(repo.cancellations, greaterThan(0));
    await cubit.close();
  });
  test('logout immediately clears private list', () async {
    final cubit = list(FakeChatRepository());
    await cubit.load();
    expect(cubit.state.items, isNotEmpty);
    await preferences.clearSession();
    expect(cubit.state.items, isEmpty);
    await cubit.close();
  });
  test('failed refresh preserves cached rows and exposes retry', () async {
    final repo = FakeChatRepository();
    final cubit = list(repo);
    await cubit.load();
    repo.failure = Exception('offline');
    await cubit.load();
    expect(cubit.state.items.length, 1);
    expect(cubit.state.error, isNotNull);
    repo.failure = null;
    await cubit.load();
    expect(cubit.state.error, isNull);
    await cubit.close();
  });
  test('pagination deduplicates authoritative IDs', () async {
    var calls = 0;
    final cubit = ChatListCubit<ChatMessage>(
      fetch: (_) async =>
          ChatPage([message], continuation: ++calls == 1 ? 'opaque' : null),
      idOf: (m) => m.id,
      cancel: () {},
    );
    await cubit.load();
    await cubit.load(more: true);
    expect(cubit.state.items.length, 1);
    expect(cubit.state.continuation, isNull);
    await cubit.close();
  });
  test(
    'older messages prepend without changing existing chronological order',
    () async {
      var call = 0;
      const older = ChatMessage(
        id: 'older',
        senderId: 'other',
        kind: ChatMessageKind.text,
      );
      final cubit = ChatListCubit<ChatMessage>(
        prependPages: true,
        fetch: (_) async => ++call == 1
            ? ChatPage([message], continuation: 'older')
            : ChatPage([older]),
        idOf: (m) => m.id,
        cancel: () {},
      );
      await cubit.load();
      await cubit.load(more: true);
      expect(cubit.state.items.map((m) => m.id), ['older', 'message-1']);
      await cubit.close();
    },
  );
  test('no pagination request without continuation', () async {
    final repo = FakeChatRepository();
    final cubit = list(repo);
    await cubit.load();
    await cubit.load(more: true);
    expect(repo.loads, 1);
    await cubit.close();
  });
  test('confirmed send merges once even when a REST page omitted it', () async {
    final cubit = ChatListCubit<ChatMessage>(
      fetch: (_) async => ChatPage(const <ChatMessage>[]),
      idOf: (m) => m.id,
      cancel: () {},
    );
    await cubit.load();
    cubit.appendConfirmed(message, session: preferences.sessionRevision);
    cubit.appendConfirmed(message, session: preferences.sessionRevision);
    expect(cubit.state.items.single.id, message.id);
    await cubit.close();
  });
  test(
    'confirmed send from an expired session cannot populate a new account',
    () async {
      final session = preferences.sessionRevision;
      final cubit = ChatListCubit<ChatMessage>(
        fetch: (_) async => ChatPage(const <ChatMessage>[]),
        idOf: (m) => m.id,
        cancel: () {},
      );
      await preferences.saveToken('replacement-account');
      cubit.appendConfirmed(message, session: session);
      expect(cubit.state.items, isEmpty);
      await cubit.close();
    },
  );
  test('repeated continuation cannot create endless pagination', () async {
    final cubit = ChatListCubit<ChatMessage>(
      fetch: (_) async => ChatPage([message], continuation: 'same'),
      idOf: (m) => m.id,
      cancel: () {},
    );
    await cubit.load();
    await cubit.load(more: true);
    expect(cubit.state.continuation, isNull);
    await cubit.close();
  });
  test('sending coalesces taps and only reconciles server success', () async {
    final repo = FakeChatRepository()..sending = Completer();
    final accepted = <ChatMessage>[];
    final cubit = ChatComposerCubit(
      repository: repo,
      conversation: conversation,
      onSent: accepted.add,
    );
    cubit.edit('Hello');
    final pending = cubit.send();
    await cubit.send();
    expect(repo.sends, 1);
    expect(cubit.state.sending, true);
    repo.sending!.complete(message);
    await pending;
    expect(accepted.single.id, message.id);
    expect(cubit.state.draft, '');
    await cubit.close();
  });
  test('empty message sends nothing', () async {
    final repo = FakeChatRepository();
    final cubit = ChatComposerCubit(
      repository: repo,
      conversation: conversation,
      onSent: (_) {},
    );
    cubit.edit('   ');
    await cubit.send();
    expect(repo.sends, 0);
    await cubit.close();
  });
  test(
    'failed send keeps text in the failed bubble, not the draft, without automatic retry',
    () async {
      final repo = FakeChatRepository()..failure = Exception('offline');
      final cubit = ChatComposerCubit(
        repository: repo,
        conversation: conversation,
        onSent: (_) {},
      );
      cubit.edit('Draft 😀\nمرحبا');
      await cubit.send();
      expect(cubit.state.draft, isEmpty);
      expect(cubit.state.localMessages.single.text, 'Draft 😀\nمرحبا');
      expect(cubit.state.localMessages.single.delivery, ChatDelivery.failed);
      expect(cubit.state.error, isNotNull);
      expect(repo.sends, 1);
      await cubit.close();
    },
  );
  test(
    'text typed during an in-flight send is kept as the new draft',
    () async {
      final repo = FakeChatRepository()..sending = Completer<ChatMessage>();
      final cubit = ChatComposerCubit(
        repository: repo,
        conversation: conversation,
        onSent: (_) {},
      );
      cubit.edit('first');
      final sent = cubit.send();
      expect(cubit.state.draft, isEmpty);
      expect(cubit.state.sending, true);
      cubit.edit('second');
      expect(cubit.state.sending, true);
      repo.sending!.complete(message);
      await sent;
      expect(cubit.state.draft, 'second');
      expect(cubit.state.localMessages, isEmpty);
      await cubit.close();
    },
  );

  test('send rejected before a bubble exists keeps the draft', () async {
    final repo = FakeChatRepository()
      ..capabilities = const ChatCapabilities(list: true, messages: true);
    final cubit = ChatComposerCubit(
      repository: repo,
      conversation: conversation,
      onSent: (_) {},
    );
    cubit.edit('kept');
    await cubit.send();
    expect(cubit.state.draft, 'kept');
    expect(cubit.state.localMessages, isEmpty);
    expect(repo.sends, 0);
    await cubit.close();
  });

  test('draft survives leaving and reopening route', () async {
    final repo = FakeChatRepository();
    final first = ChatComposerCubit(
      repository: repo,
      conversation: conversation,
      onSent: (_) {},
    );
    first.edit('Unsent draft');
    await first.close();
    final second = ChatComposerCubit(
      repository: repo,
      conversation: conversation,
      onSent: (_) {},
    );
    expect(second.state.draft, 'Unsent draft');
    await second.close();
  });
  test(
    'account switching clears draft and prevents old composer sends',
    () async {
      final repo = FakeChatRepository();
      final cubit = ChatComposerCubit(
        repository: repo,
        conversation: conversation,
        onSent: (_) {},
      );
      cubit.edit('Private');
      await preferences.saveToken('new-session');
      expect(cubit.state.draft, '');
      cubit.edit('late edit');
      await cubit.send();
      expect(repo.sends, 0);
      expect(cubit.state.draft, '');
      await cubit.close();
    },
  );
  test('late send response cannot update replacement account', () async {
    final repo = FakeChatRepository()..sending = Completer();
    var callbacks = 0;
    final cubit = ChatComposerCubit(
      repository: repo,
      conversation: conversation,
      onSent: (_) => callbacks++,
    );
    cubit.edit('Hello');
    final pending = cubit.send();
    await preferences.clearSession();
    repo.sending!.complete(message);
    await pending;
    expect(callbacks, 0);
    expect(cubit.state.draft, '');
    await cubit.close();
  });
  test('unconfirmed conversation permission prevents sending', () async {
    final repo = FakeChatRepository();
    final cubit = ChatComposerCubit(
      repository: repo,
      conversation: const ChatConversation(
        id: 'closed',
        participant: participant,
      ),
      onSent: (_) {},
    );
    cubit.edit('Hello');
    await cubit.send();
    expect(repo.sends, 0);
    await cubit.close();
  });
  test(
    'realtime start subscribes once and deduplicates only current-account events',
    () async {
      final transport = _Transport();
      var count = 0;
      final coordinator = ChatRealtimeCoordinator(
        transport: transport,
        sessionRevision: 5,
        onActivity: () => count++,
      );
      await Future.wait([coordinator.start(), coordinator.start()]);
      expect(transport.connects, 1);
      transport.controller.add(
        const ChatRealtimeEvent(id: '1', sessionRevision: 5),
      );
      transport.controller.add(
        const ChatRealtimeEvent(id: '1', sessionRevision: 5),
      );
      transport.controller.add(
        const ChatRealtimeEvent(id: '2', sessionRevision: 4),
      );
      await Future<void>.delayed(Duration.zero);
      expect(count, 1);
      await coordinator.dispose();
      transport.controller.add(
        const ChatRealtimeEvent(id: '3', sessionRevision: 5),
      );
      await Future<void>.delayed(Duration.zero);
      expect(count, 1);
      expect(transport.disconnects, 1);
      await transport.controller.close();
    },
  );
}

class _Transport implements ChatRealtimeTransport {
  final controller = StreamController<ChatRealtimeEvent>.broadcast();
  int connects = 0, disconnects = 0;
  @override
  Stream<ChatRealtimeEvent> get events => controller.stream;
  @override
  Future<void> connect() async {
    connects++;
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
  }

  @override
  Future<void> subscribe(String verifiedChannel) async {}
  @override
  Future<void> unsubscribe(String verifiedChannel) async {}
}
