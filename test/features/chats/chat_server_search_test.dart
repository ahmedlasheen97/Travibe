import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/data/chat_repository.dart';
import 'package:travibe/features/chats/screens/chats_screen.dart';
import 'chat_fakes.dart';

class ServerSearchFake extends FakeChatRepository
    implements ConversationSearchRepository {
  final queries = <String>[];
  final pending = <String, Completer<ChatPage<ChatConversation>>>{};
  @override
  Future<ChatPage<ChatConversation>> searchConversations(
    String search, {
    String? continuation,
    bool requests = false,
  }) {
    queries.add(search);
    if (search.isEmpty) return conversations(requests: requests);
    return (pending[search] ??= Completer()).future;
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('synthetic');
  });
  for (final requests in [false, true]) {
    testWidgets(
      requests
          ? 'Requests loads server results without a visible search field'
          : 'server inbox search debounce rejects stale results',
      (tester) async {
        final repo = ServerSearchFake();
        await tester.pumpWidget(
          ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, _) => MaterialApp(
              home: ChatsScreen(repository: repo, requests: requests),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        if (requests) {
          expect(find.byType(TextField), findsNothing);
          expect(find.text('Requests'), findsOneWidget);
          expect(repo.queries, ['']);
          await tester.pumpWidget(const SizedBox());
          return;
        }
        await tester.enterText(find.byType(TextField), 'alice');
        await tester.pump(const Duration(milliseconds: 349));
        expect(repo.queries, ['']);
        await tester.pump(const Duration(milliseconds: 1));
        expect(repo.queries, ['', 'alice']);
        await tester.enterText(find.byType(TextField), 'bob');
        repo.pending['alice']!.complete(
          ChatPage([
            const ChatConversation(
              id: 'old',
              participant: ChatParticipant(id: '6', name: 'Stale Alice'),
            ),
          ]),
        );
        await tester.pump();
        expect(find.text('Stale Alice'), findsNothing);
        await tester.pump(const Duration(milliseconds: 350));
        repo.pending['bob']!.complete(
          ChatPage([
            const ChatConversation(
              id: 'new',
              participant: ChatParticipant(id: '7', name: 'Bob'),
            ),
          ]),
        );
        await tester.pump();
        expect(find.text('Bob'), findsOneWidget);
        expect(repo.queries, ['', 'alice', 'bob']);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
