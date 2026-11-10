import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/chats/cubit/chat_discovery_cubit.dart';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/screens/new_conversation_screen.dart';
import 'package:travibe/features/chats/screens/conversation_screen.dart';
import 'package:travibe/features/search/data/search_repo.dart';
import 'package:travibe/features/search/data/users_page_model.dart';
import 'chat_fakes.dart';

PublicUserModel person(int id, {bool blocked = false}) =>
    PublicUserModel.fromJson({
      'id': id,
      'name': 'Traveler $id',
      'username': 'traveler$id',
      'is_blocked': blocked,
    });
UsersPageModel page(
  List<PublicUserModel> users, {
  int current = 1,
  int last = 1,
}) => UsersPageModel(
  users: users,
  currentPage: current,
  lastPage: last,
  total: users.length,
);

class Search extends SearchRepo {
  final calls = <(String, int)>[];
  final responses = <Completer<UsersPageModel>>[];
  int identities = 0;
  @override
  Future<String> getCurrentUserId() async {
    identities++;
    return '1';
  }

  @override
  Future<UsersPageModel> searchUsers(String query, {int page = 1}) {
    calls.add((query, page));
    final result = Completer<UsersPageModel>();
    responses.add(result);
    return result.future;
  }
}

class Conversations extends FakeChatRepository {
  final created = <String>[];
  final result = Completer<ChatConversation>();
  @override
  Future<ChatConversation> create(String id) {
    created.add(id);
    return result.future;
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('discovery-test');
  });
  testWidgets(
    'minimum and debounce coalesce repeated queries; stale results ignored',
    (tester) async {
      final repo = Search();
      final cubit = ChatDiscoveryCubit(repo: repo);
      cubit.query('al');
      await tester.pump(const Duration(milliseconds: 400));
      expect(repo.calls, isEmpty);
      cubit.query('alice');
      await tester.pump(const Duration(milliseconds: 349));
      expect(repo.calls, isEmpty);
      cubit.query('alice');
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(repo.calls, [('alice', 1)]);
      cubit.query('alina');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 1));
      repo.responses[1].complete(page([person(3)]));
      await tester.pump(const Duration(milliseconds: 1));
      repo.responses[0].complete(page([person(2)]));
      await tester.pump(const Duration(milliseconds: 1));
      expect(cubit.state.users.single.id, '3');
      expect(repo.identities, 1);
      await cubit.close();
    },
  );
  testWidgets(
    'filters own account and blocked users; empty success differs from failure and retry',
    (tester) async {
      final repo = Search();
      final cubit = ChatDiscoveryCubit(repo: repo, delay: Duration.zero);
      cubit.query('alice');
      await tester.pump(const Duration(milliseconds: 1));
      repo.responses[0].complete(page([person(1), person(2, blocked: true)]));
      await tester.pump(const Duration(milliseconds: 1));
      expect(cubit.state.status, ChatDiscoveryStatus.loaded);
      expect(cubit.state.filteredCount, 2);
      expect(cubit.state.users, isEmpty);
      cubit.query('alina');
      await tester.pump(const Duration(milliseconds: 1));
      repo.responses[1].completeError(ApiError(message: 'Offline'));
      await tester.pump(const Duration(milliseconds: 1));
      expect(cubit.state.status, ChatDiscoveryStatus.failure);
      expect(cubit.state.error!.message, 'Offline');
      final retry = cubit.retry();
      await tester.pump(const Duration(milliseconds: 1));
      repo.responses[2].complete(page([]));
      await retry;
      expect(cubit.state.status, ChatDiscoveryStatus.loaded);
      expect(cubit.state.filteredCount, 0);
      await cubit.close();
    },
  );
  testWidgets(
    'pagination deduplicates and a newly blocked user cannot return from a stale page',
    (tester) async {
      final repo = Search();
      final cubit = ChatDiscoveryCubit(
        repo: repo,
        currentUserId: '1',
        delay: Duration.zero,
      );
      cubit.query('trav');
      await tester.pump(const Duration(milliseconds: 1));
      repo.responses[0].complete(page([person(2)], last: 2));
      await tester.pump(const Duration(milliseconds: 1));
      final more = cubit.more();
      await tester.pump(const Duration(milliseconds: 1));
      await cubit.more();
      cubit.setBlocked({'2'});
      repo.responses[1].complete(
        page([person(2), person(3)], current: 2, last: 2),
      );
      await more;
      expect(repo.calls, [('trav', 1), ('trav', 2)]);
      expect(cubit.state.users.map((u) => u.id), ['3']);
      await cubit.close();
    },
  );
  testWidgets('account switching clears results and ignores in-flight search', (
    tester,
  ) async {
    final repo = Search();
    final cubit = ChatDiscoveryCubit(repo: repo, delay: Duration.zero);
    cubit.query('alice');
    await tester.pump(const Duration(milliseconds: 1));
    await PreferencesManager().saveToken('replacement-session');
    repo.responses.single.complete(page([person(2)]));
    await tester.pump(const Duration(milliseconds: 1));
    expect(cubit.state.users, isEmpty);
    expect(cubit.valid, isFalse);
    await cubit.close();
  });
  testWidgets('selection coalesces creation and opens returned conversation', (
    tester,
  ) async {
    final search = Search();
    final chats = Conversations();
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: ThemeData.dark(),
          home: NewConversationScreen(search: search, repository: chats),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'trav');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 1));
    search.responses.single.complete(page([person(2)]));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.tap(find.text('Traveler 2'));
    await tester.tap(find.text('Traveler 2'));
    await tester.pump(const Duration(milliseconds: 1));
    expect(chats.created, ['2']);
    chats.result.complete(
      const ChatConversation(
        id: '44',
        participant: ChatParticipant(id: '2', name: 'Traveler 2'),
        canSend: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ConversationScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
