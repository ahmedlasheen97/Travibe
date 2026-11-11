import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/chats/cubit/chat_unread_cubit.dart';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/screens/chats_screen.dart';
import 'package:travibe/features/chats/screens/conversation_screen.dart';
import 'package:travibe/features/chats/widgets/chat_widgets.dart';
import 'chat_badge_images_test.dart' show UnreadRepo, drain, thread;
import 'chat_fakes.dart';
import 'chat_widgets_test.dart' show harness;

/// Mark-read and history requests wait on gates the test controls.
class GatedReadRepo extends FakeChatRepository {
  Completer<void>? readGate;
  Completer<void>? historyGate;
  @override
  Future<void> markRead(String id) async {
    reads++;
    await readGate?.future;
  }

  @override
  Future<ChatPage<ChatMessage>> messages(
    String id, {
    String? continuation,
  }) async {
    await historyGate?.future;
    return ChatPage(messageItems);
  }
}

// The list stays mounted (offstage) under the conversation route.
Finder get _badge => find.descendant(
  of: find.byType(ChatListTile, skipOffstage: false),
  matching: find.text('2', skipOffstage: false),
  skipOffstage: false,
);

void main() {
  final prefs = PreferencesManager();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await prefs.init();
    await prefs.saveToken('fixture');
  });

  testWidgets(
    'opening a chat clears its badge immediately and a stale refresh cannot bring it back',
    (tester) async {
      final repo = GatedReadRepo()..items = [thread('42', 2)];
      await tester.pumpWidget(harness(ChatsScreen(repository: repo)));
      await tester.pumpAndSettle();
      expect(_badge, findsOneWidget);

      repo.readGate = Completer();
      await tester.tap(find.text('Test Person'));
      await tester.pump();
      expect(_badge, findsNothing); // Optimistic, before the read settles.
      expect(repo.reads, greaterThanOrEqualTo(1));

      // A list refresh starts before the read settles and returns the old count.
      final stale = Completer<ChatPage<ChatConversation>>();
      repo.loading = stale;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(repo.loads, 3); // The stale inbox GET is in flight.

      repo.readGate!.complete();
      await tester.pump();
      stale.complete(ChatPage([thread('42', 2)]));
      repo
        ..loading = null
        ..items = [thread('42', 0)];
      await tester.pumpAndSettle();
      // The stale page landed after the read; the badge stays cleared.
      expect(_badge, findsNothing);

      Navigator.of(tester.element(find.byType(ConversationScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(ChatsScreen), findsOneWidget);
      expect(_badge, findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'going back before history loads still marks the chat read and clears the badge',
    (tester) async {
      final repo = GatedReadRepo()
        ..items = [thread('42', 2)]
        ..historyGate = Completer();
      await tester.pumpWidget(harness(ChatsScreen(repository: repo)));
      await tester.pumpAndSettle();
      expect(_badge, findsOneWidget);

      repo.readGate = Completer();
      await tester.tap(find.text('Test Person'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      Navigator.of(tester.element(find.byType(ConversationScreen))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(repo.reads, 1);
      expect(_badge, findsNothing);

      repo.items = [thread('42', 0)];
      repo.readGate!.complete();
      repo.historyGate!.complete();
      await tester.pumpAndSettle();
      expect(_badge, findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('failed read restores the server count', (tester) async {
    final repo = GatedReadRepo()..items = [thread('42', 2)];
    await tester.pumpWidget(harness(ChatsScreen(repository: repo)));
    await tester.pumpAndSettle();
    repo.readGate = Completer();
    await tester.tap(find.text('Test Person'));
    await tester.pumpAndSettle();
    expect(_badge, findsNothing);
    repo.readGate!.completeError(ApiError(message: 'Read failed'));
    Navigator.of(tester.element(find.byType(ConversationScreen))).pop();
    await tester.pumpAndSettle();
    expect(_badge, findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'a conversation opened directly marks read at open, before history loads',
    (tester) async {
      final repo = GatedReadRepo()..historyGate = Completer();
      await tester.pumpWidget(
        harness(
          ConversationScreen(
            conversation: thread('42', 2),
            repository: repo,
            currentUserId: 'self',
          ),
        ),
      );
      await tester.pump();
      expect(repo.reads, 1);
      repo.historyGate!.complete();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );

  group('ChatUnreadCubit.trackRead', () {
    late UnreadRepo repo;
    late ChatUnreadCubit unread;
    final owner = Object();
    setUp(() async {
      SharedPreferences.setMockInitialValues({'_token': 'fixture-account'});
      await prefs.init();
      repo = UnreadRepo();
      repo.pages['inbox:first'] = ChatPage([thread('42', 2), thread('7', 1)]);
      unread = ChatUnreadCubit(
        repository: repo,
        reconcileInterval: Duration.zero,
      );
      unread.account('5');
      unread.attach(owner);
      await drain();
      expect(unread.state.count, 3);
    });
    tearDown(() async {
      if (!unread.isClosed) await unread.close();
      await prefs.clear();
    });

    test(
      'drops the total immediately and ignores a scan that predates the read',
      () async {
        repo.gate = Completer();
        unawaited(unread.refresh()); // Stale scan in flight.
        await drain();
        final read = Completer<void>();
        final tracked = unread.trackRead('42', read.future);
        expect(unread.state.count, 1);

        repo.gate!.complete(); // Stale scan still reports 42 -> 2.
        await drain();
        expect(unread.state.count, 1);

        repo.gate = null;
        repo.pages['inbox:first'] = ChatPage([thread('42', 0), thread('7', 1)]);
        read.complete();
        await tracked;
        await drain();
        expect(unread.state.count, 1);
        expect(unread.state.confirmed, isTrue);
      },
    );

    test('a failed read rolls the total back to the server count', () async {
      final read = Completer<void>();
      final tracked = unread.trackRead('42', read.future);
      expect(unread.state.count, 1);
      read.completeError(ApiError(message: 'Read failed'));
      await tracked;
      await drain();
      expect(unread.state.count, 3);
    });
  });
}
