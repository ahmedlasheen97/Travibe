import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/chats/cubit/chat_cubit.dart';
import 'package:travibe/features/chats/cubit/chat_unread_cubit.dart';
import 'package:travibe/features/chats/data/chat_history_cache.dart';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/data/chat_broadcast_event.dart';
import 'package:travibe/features/chats/data/chat_repository.dart';
import 'package:travibe/features/chats/screens/chats_screen.dart';
import 'package:travibe/features/chats/widgets/chat_history_image.dart';
import 'package:travibe/features/chats/widgets/chat_reverb_host.dart';
import 'package:travibe/features/chats/widgets/chat_widgets.dart';
import 'package:travibe/features/home/widgets/home_top_bar.dart';
import 'chat_fakes.dart';
import 'chat_widgets_test.dart' show harness;
import 'chat_badge_images_test.dart' show UnreadRepo, thread;
import 'chat_loading_lifecycle_test.dart' show ImageClient;
import 'message_requests_test.dart' show RequestsReverb;

class InboxRepo extends FakeChatRepository {
  Completer<ChatPage<ChatConversation>>? inboxGate;
  Completer<ChatPage<ChatConversation>>? countGate;
  int count = 0;
  Object? inboxFailure;
  @override
  Future<ChatPage<ChatConversation>> conversations({
    String? continuation,
    bool requests = false,
  }) async {
    loads++;
    if (requests) return countGate?.future ?? ChatPage([], total: count);
    if (inboxFailure != null) throw inboxFailure!;
    return inboxGate?.future ?? ChatPage(items);
  }
}

class SearchInboxRepo extends InboxRepo
    implements ConversationSearchRepository {
  @override
  Future<ChatPage<ChatConversation>> searchConversations(
    String query, {
    String? continuation,
    bool requests = false,
  }) async => query.isEmpty
      ? conversations(continuation: continuation, requests: requests)
      : ChatPage([thread('search-only', 0)]);
}

Future<void> drain() async {
  for (var i = 0; i < 40; i++) {
    await Future<void>.microtask(() {});
  }
}

void main() {
  final prefs = PreferencesManager();
  late List<int> bytes;
  setUpAll(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 40, 80),
      Paint()..color = Colors.orange,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(40, 80);
    bytes = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await prefs.init();
    await prefs.saveToken('fixture-account');
  });

  test(
    'numeric unread sums every page and scope, deduplicates IDs, and never counts outgoing locally',
    () async {
      final repo = UnreadRepo();
      repo.pages['inbox:first'] = ChatPage([
        thread('a', 4),
      ], continuation: 'next');
      repo.pages['inbox:next'] = ChatPage([thread('b', 6)]);
      repo.pages['requests:first'] = ChatPage([thread('c', 3), thread('a', 4)]);
      final unread = ChatUnreadCubit(
        repository: repo,
        reconcileInterval: Duration.zero,
      );
      unread.account('self');
      unread.attach(Object());
      await drain();
      expect(unread.state.count, 13);
      expect(unread.state.confirmed, true);
      expect(repo.calls, ['inbox:first', 'requests:first', 'inbox:next']);
      // A new hint is a REST reconciliation, not an event-side increment.
      await unread.refresh();
      await unread.refresh();
      expect(unread.state.count, 13);
      repo.pages['inbox:first'] = ChatPage([
        thread('a', 0),
      ], continuation: 'next');
      repo.pages['requests:first'] = ChatPage([thread('c', 0), thread('a', 0)]);
      await unread.refresh();
      expect(unread.state.count, 6);
      repo.failure = const SocketException('offline');
      await unread.refresh();
      expect(unread.state.count, 6);
      expect(unread.state.error, true);
      await prefs.saveToken('other-account');
      expect(unread.state.count, 0);
      expect(unread.state.confirmed, false);
      await unread.close();
    },
  );

  test(
    'incomplete or conflicting snapshots never publish partial unread totals',
    () async {
      final repo = UnreadRepo();
      repo.pages['inbox:first'] = ChatPage([thread('a', 9)]);
      final unread = ChatUnreadCubit(
        repository: repo,
        reconcileInterval: Duration.zero,
      );
      unread.account('self');
      unread.attach(Object());
      await drain();
      expect(unread.state.count, 9);
      repo.pages['requests:first'] = ChatPage([thread('a', 2)]);
      await unread.refresh();
      expect(unread.state.count, 9);
      expect(unread.state.error, true);
      repo.pages['requests:first'] = ChatPage([]);
      repo.pages['inbox:first'] = ChatPage([
        thread('a', 1),
      ], continuation: 'cycle');
      repo.pages['inbox:cycle'] = ChatPage([
        thread('a', 1),
      ], continuation: 'cycle');
      await unread.refresh();
      expect(unread.state.count, 9);
      expect(unread.state.error, true);
      await unread.close();
    },
  );

  for (final count in [0, 1, 9, 99, 100, 245]) {
    testWidgets(
      'Home numeric badge renders $count without covering Chat icon at 320px',
      (tester) async {
        tester.view.physicalSize = const Size(320, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = UnreadRepo();
        repo.pages['inbox:first'] = ChatPage([thread('a', count)]);
        final unread = ChatUnreadCubit(
          repository: repo,
          reconcileInterval: Duration.zero,
        );
        final reverb = RequestsReverb();
        unread.account('self');
        unread.attach(Object());
        await drain();
        await tester.pumpWidget(
          ChatReverbScope(
            service: reverb,
            unread: unread,
            child: harness(
              Scaffold(
                body: HomeTopBar(
                  onMessagesTap: () {},
                  onNotificationsTap: () {},
                ),
              ),
              scale: 1.5,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final badge = find.byKey(const ValueKey('chat-unread-badge'));
        expect(badge, count == 0 ? findsNothing : findsOneWidget);
        if (count > 0) {
          expect(
            find.descendant(
              of: badge,
              matching: find.text(count > 99 ? '99+' : '$count'),
            ),
            findsOneWidget,
          );
          final bounds = tester.getRect(
            find.byKey(const ValueKey('home-messages-button')),
          );
          expect(
            tester.getRect(badge).center.dx,
            greaterThan(bounds.center.dx),
          );
          expect(tester.getRect(badge).center.dy, lessThan(bounds.center.dy));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        if (!unread.isClosed) await unread.close();
        reverb.dispose();
      },
    );
  }

  for (final count in [0, 1, 7]) {
    testWidgets(
      'Requests label uses server total $count rather than loaded row count',
      (tester) async {
        final repo = InboxRepo()..count = count;
        await tester.pumpWidget(harness(ChatsScreen(repository: repo)));
        await tester.pumpAndSettle();
        expect(
          find.text(count == 0 ? 'Requests' : 'Requests ($count)'),
          findsOneWidget,
        );
        expect(find.text('Requests (0)'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'Inbox restores cache on route recreation and silently reconciles; offline keeps rows',
    (tester) async {
      final repo = InboxRepo();
      await tester.pumpWidget(
        harness(
          Builder(
            builder: (context) => TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ChatsScreen(repository: repo),
                  ),
                );
              },
              child: const Text('Open Chats'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open Chats'));
      await tester.pumpAndSettle();
      expect(find.text('Test Person'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      repo.inboxGate = Completer();
      await tester.tap(find.text('Open Chats'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Test Person'), findsOneWidget);
      expect(find.byType(ChatsLoadingSkeleton), findsNothing);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      repo.inboxGate!.completeError(const SocketException('offline'));
      await tester.pumpAndSettle();
      expect(find.text('Test Person'), findsOneWidget);
      expect(find.text('No messages yet'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      repo.inboxGate = null;
      repo.items = [thread('fresh', 2)];
      await tester.tap(find.text('Open Chats'));
      await tester.pumpAndSettle();
      expect(
        find.text('Test Person'),
        findsOneWidget,
      ); // updated canonical participant
      expect(find.byKey(const ValueKey('fresh')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'loaded empty Inbox is not displayed as empty while refreshing or offline',
    (tester) async {
      final repo = InboxRepo()..items = [];
      await tester.pumpWidget(harness(ChatsScreen(repository: repo)));
      await tester.pumpAndSettle();
      expect(find.text('No messages yet'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      repo.inboxGate = Completer();
      await tester.pumpWidget(harness(ChatsScreen(repository: repo)));
      await tester.pump();
      expect(find.byType(ChatsLoadingSkeleton), findsNothing);
      expect(find.text('No messages yet'), findsNothing);
      repo.inboxGate!.completeError(const SocketException('offline'));
      await tester.pumpAndSettle();
      expect(find.text('No messages yet'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('server search results do not overwrite unfiltered Inbox cache', (
    tester,
  ) async {
    final repo = SearchInboxRepo();
    await tester.pumpWidget(harness(ChatsScreen(repository: repo)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'search');
    await tester.pump(const Duration(milliseconds: 360));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-only')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    repo.inboxGate = Completer();
    await tester.pumpWidget(harness(ChatsScreen(repository: repo)));
    await tester.pump();
    expect(find.byKey(ValueKey(conversation.id)), findsOneWidget);
    expect(find.byKey(const ValueKey('search-only')), findsNothing);
    repo.inboxGate!.complete(ChatPage([conversation]));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'bounded Inbox cache evicts LRU entries, caps retained rows and clears on account change',
    () async {
      final cache = ChatHistoryCache();
      for (var i = 0; i < 9; i++) {
        cache.write(i, i, prefs.sessionRevision, group: 'inbox');
      }
      expect(cache.read<int>(0, group: 'inbox'), isNull);
      expect(cache.read<int>(8, group: 'inbox'), 8);
      final cubit = ChatListCubit<ChatConversation>(
        fetch: (_) async => ChatPage(
          List.generate(201, (i) => thread('$i', 0)),
          continuation: 'next',
        ),
        idOf: (c) => c.id,
        cancel: () {},
        cache: cache,
        cacheKey: 'bounded',
        cacheGroup: 'inbox',
        cacheItemLimit: 200,
      );
      await cubit.load();
      await cubit.close();
      final reopened = ChatListCubit<ChatConversation>(
        fetch: (_) async => ChatPage([]),
        idOf: (c) => c.id,
        cancel: () {},
        cache: cache,
        cacheKey: 'bounded',
        cacheGroup: 'inbox',
        cacheItemLimit: 200,
      );
      expect(reopened.state.items.length, 200);
      expect(reopened.state.continuation, isNull);
      await prefs.saveToken('replacement');
      expect(reopened.state.items, isEmpty);
      expect(cache.read<int>(8, group: 'inbox'), isNull);
      await reopened.close();
      cache.dispose();
    },
  );

  testWidgets(
    'sent image cold download uses quiet fixed bounds; broken URLs show download retry, never upload state',
    (tester) async {
      for (final succeeds in [true, false]) {
        final client = ImageClient(succeeds ? bytes : []);
        debugNetworkImageHttpClientProvider = () => client;
        final url = Uri.parse(
          'https://fixtures.invalid/final-image-$succeeds.png',
        );
        await tester.pumpWidget(
          harness(
            Scaffold(
              body: ChatMessageBubble(
                outgoing: true,
                message: ChatMessage(
                  id: 'image',
                  senderId: 'self',
                  kind: ChatMessageKind.image,
                  mediaUrl: url,
                  mediaWidth: 40,
                  mediaHeight: 80,
                ),
              ),
            ),
          ),
        );
        final image = find.byType(ChatHistoryImage);
        final before = tester.getSize(image);
        expect(before.width / before.height, closeTo(.5, .001));
        expect(
          find.byKey(const ValueKey('chat-image-download-placeholder')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('chat-image-upload-overlay')),
          findsNothing,
        );
        expect(find.byType(CupertinoActivityIndicator), findsNothing);
        client.gate.complete();
        await tester.runAsync(
          () => precacheImage(
            NetworkImage(url.toString()),
            tester.element(image),
            onError: (Object _, StackTrace? _) {},
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.getSize(image), before);
        expect(
          find.byKey(const ValueKey('chat-image-download-placeholder')),
          findsNothing,
        );
        expect(find.byType(CupertinoActivityIndicator), findsNothing);
        expect(
          find.text('Image unavailable. Retry'),
          succeeds ? findsNothing : findsOneWidget,
        );
        expect(client.requests, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        debugNetworkImageHttpClientProvider = null;
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      }
    },
  );

  test(
    'documented media dimensions parse and survive receipt reconciliation',
    () {
      final message = ChatMessage.fromJson({
        'id': 1,
        'conversation_id': 1,
        'sender_id': 2,
        'type': 'image',
        'is_deleted': false,
        'media': [
          {
            'id': 3,
            'url': 'https://fixtures.invalid/image.png',
            'width': 40,
            'height': 80,
          },
        ],
      });
      expect(message.mediaWidth, 40);
      expect(message.mediaHeight, 80);
      final merged = reconcileChatMessage(message, message);
      expect(merged.mediaWidth, 40);
      expect(merged.mediaHeight, 80);
      final read = ChatMessagesRead(
        '1',
        '3',
        '1',
        DateTime.utc(2026, 11, 10),
      ).apply([message], currentUserId: '2').single;
      expect(read.delivery, ChatDelivery.seen);
      expect(read.mediaWidth, 40);
      expect(read.mediaHeight, 80);
    },
  );
}
