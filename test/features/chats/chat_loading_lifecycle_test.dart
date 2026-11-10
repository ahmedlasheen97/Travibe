import 'dart:async';
import 'dart:io';
import 'package:travibe/features/chats/widgets/chat_history_image.dart';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/chats/cubit/chat_cubit.dart';
import 'package:travibe/features/chats/data/chat_history_cache.dart';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/screens/conversation_screen.dart';
import 'package:travibe/features/chats/widgets/chat_loading.dart';
import 'chat_fakes.dart';
import 'message_requests_test.dart' show RequestsRepo, accepted;
import 'chat_widgets_test.dart' show harness;

class HistoryRepo extends FakeChatRepository {
  Completer<ChatPage<ChatMessage>>? gate;
  int historyLoads = 0;
  Object? historyFailure;
  @override
  Future<ChatPage<ChatMessage>> messages(
    String id, {
    String? continuation,
  }) async {
    historyLoads++;
    if (historyFailure != null) throw historyFailure!;
    return gate?.future ?? ChatPage(messageItems);
  }
}

class ChangesRepo extends RequestsRepo {
  ChangesRepo() {
    isAccepted = true;
    messageItems = [oldMessage];
  }
  static final oldMessage = ChatMessage(
    id: '101',
    senderId: '7',
    kind: ChatMessageKind.text,
    text: 'Older cached fixture',
    updatedAt: DateTime.utc(2026, 11, 1),
  );
  final cursors = <DateTime?>[];
  @override
  Future<ChatPage<ChatMessage>> messageChanges(
    String id, {
    String? afterId,
    DateTime? updatedSince,
    String? continuation,
  }) async {
    cursors.add(updatedSince);
    return ChatPage([oldMessage.asDeleted()]);
  }
}

class ImageClient implements HttpClient {
  ImageClient(this.bytes);
  final List<int> bytes;
  int requests = 0;
  final gate = Completer<void>();
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requests++;
    await gate.future;
    return ImageRequest(bytes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ImageRequest implements HttpClientRequest {
  ImageRequest(this.bytes);
  final List<int> bytes;
  @override
  Future<HttpClientResponse> close() async => ImageResponse(bytes);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ImageResponse extends Stream<List<int>> implements HttpClientResponse {
  ImageResponse(this.bytes);
  final List<int> bytes;
  @override
  int get statusCode => 200;
  @override
  int get contentLength => bytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final prefs = PreferencesManager();
  late ChatHistoryCache cache;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await prefs.init();
    await prefs.saveToken('fixture-session');
    cache = ChatHistoryCache();
  });
  tearDown(() => cache.dispose());
  ChatListCubit<ChatMessage> history(
    Future<ChatPage<ChatMessage>> Function(String?) fetch,
  ) => ChatListCubit<ChatMessage>(
    fetch: fetch,
    idOf: (m) => m.id,
    cancel: () {},
    cache: cache,
    cacheKey: 'thread',
    mergeRefresh: true,
    prependPages: true,
    reconcile: reconcileChatMessage,
  );

  test(
    'first open is initial loading, reopen immediately restores history and cursor',
    () async {
      var loads = 0;
      Future<ChatPage<ChatMessage>> fetch(String? _) async {
        loads++;
        return ChatPage([message], continuation: 'older');
      }

      var cubit = history(fetch);
      expect(cubit.state.hasLoaded, false);
      await cubit.load();
      await cubit.close();
      cubit = history(fetch);
      expect(cubit.state.items.single.id, message.id);
      expect(cubit.state.hasLoaded, true);
      expect(cubit.state.continuation, 'older');
      expect(loads, 1);
      await cubit.load();
      expect(loads, 2); // Cache never suppresses the canonical refresh.
      expect(cubit.state.items.length, 1);
      await cubit.close();
    },
  );

  test(
    'background refresh success/failure retain cached history including realtime updates',
    () async {
      final first = history((_) async => ChatPage([message]));
      await first.load();
      await first.close();
      final gate = Completer<ChatPage<ChatMessage>>();
      final cubit = history((_) => gate.future);
      final refresh = cubit.load();
      expect(cubit.state.loading, true);
      expect(cubit.state.loadingMore, false);
      expect(cubit.state.items.length, 1);
      const incoming = ChatMessage(
        id: 'new',
        senderId: 'other',
        kind: ChatMessageKind.text,
        text: 'Incoming fixture',
      );
      cubit.appendConfirmed(incoming, session: prefs.sessionRevision);
      gate.complete(ChatPage([message]));
      await refresh;
      expect(
        cubit.state.items.map((m) => m.id),
        containsAll([message.id, 'new']),
      );
      await cubit.close();
      final offline = history(
        (_) async => throw const SocketException('offline'),
      );
      await offline.load();
      expect(offline.state.hasLoaded, true);
      expect(offline.state.items.length, 2);
      expect(offline.state.error, isNotNull);
      await offline.close();
    },
  );

  test(
    'confirmed deletion cannot resurrect after route reopening or stale REST',
    () async {
      final first = history((_) async => ChatPage([message]));
      await first.load();
      first.removeConfirmed(message.id, session: prefs.sessionRevision);
      await first.close();
      final reopened = history((_) async => ChatPage([message]));
      await reopened.load();
      expect(reopened.state.items, isEmpty);
      expect(reopened.state.hasLoaded, true);
      await reopened.close();
    },
  );

  test(
    'pagination keeps history and uses the older-page loading state',
    () async {
      final gate = Completer<ChatPage<ChatMessage>>();
      final cubit = history(
        (next) async => next == null
            ? ChatPage([message], continuation: 'older')
            : gate.future,
      );
      await cubit.load();
      final more = cubit.load(more: true);
      expect(cubit.state.loadingMore, true);
      expect(cubit.state.items.length, 1);
      gate.complete(ChatPage([message]));
      await more;
      expect(cubit.state.loadingMore, false);
      expect(cubit.state.items.length, 1);
      await cubit.close();
    },
  );

  test(
    'late old-account responses and snapshots do not cross sessions',
    () async {
      final gate = Completer<ChatPage<ChatMessage>>();
      final cubit = history((_) => gate.future);
      final pending = cubit.load();
      await prefs.saveToken('different-session');
      gate.complete(ChatPage([message]));
      await pending;
      expect(cubit.state.items, isEmpty);
      final next = history((_) async => ChatPage([]));
      expect(next.state.hasLoaded, false);
      expect(next.state.items, isEmpty);
      await cubit.close();
      await next.close();
    },
  );

  test(
    'failed outbox survives reopening with ambiguity protection and is cleared on logout',
    () async {
      final repo = FakeChatRepository()
        ..failure = const SocketException('offline');
      ChatComposerCubit composer() => ChatComposerCubit(
        repository: repo,
        conversation: conversation,
        onSent: (_) {},
        cacheKey: 'outbox',
      );
      var cubit = composer();
      cubit.edit('Unsent fixture');
      await cubit.send();
      final id = cubit.state.localMessages.single.id;
      await cubit.close();
      cubit = composer();
      expect(cubit.state.localMessages.single.delivery, ChatDelivery.failed);
      expect(cubit.retryNeedsConfirmation(id), true);
      expect(cubit.state.draft, 'Unsent fixture');
      await cubit.close();
      await prefs.clearSession();
      await prefs.saveToken('new-session');
      cubit = composer();
      expect(cubit.state.localMessages, isEmpty);
      await cubit.close();
    },
  );

  testWidgets(
    'rapid route reopening renders cached history during offline/background refresh without skeleton or spinner',
    (tester) async {
      final repo = HistoryRepo();
      await tester.pumpWidget(
        harness(
          Builder(
            builder: (context) => TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ConversationScreen(
                      conversation: conversation,
                      repository: repo,
                      currentUserId: 'self',
                    ),
                  ),
                );
              },
              child: const Text('Open thread'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open thread'));
      await tester.pumpAndSettle();
      expect(find.text('Test message'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      repo.gate = Completer();
      await tester.tap(find.text('Open thread'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Test message'), findsOneWidget);
      expect(find.byType(ChatHistorySkeleton), findsNothing);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      repo.gate!.completeError(const SocketException('offline'));
      await tester.pump();
      expect(find.text('Test message'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(repo.historyLoads, 2);
    },
  );

  testWidgets(
    'first uncached route shows history skeleton until request completes',
    (tester) async {
      final repo = HistoryRepo()..gate = Completer();
      await tester.pumpWidget(
        harness(
          ConversationScreen(
            conversation: conversation,
            repository: repo,
            currentUserId: 'self',
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ChatHistorySkeleton), findsOneWidget);
      repo.gate!.complete(ChatPage([message]));
      await tester.pumpAndSettle();
      expect(find.byType(ChatHistorySkeleton), findsNothing);
      expect(find.text('Test message'), findsOneWidget);
    },
  );
  testWidgets(
    'sent image uses a download placeholder on cold cache and reuses decoded geometry on reopen',
    (tester) async {
      late List<int> bytes;
      await tester.runAsync(() async {
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
      final client = ImageClient(bytes);
      debugNetworkImageHttpClientProvider = () => client;
      addTearDown(() {
        debugNetworkImageHttpClientProvider = null;
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      });
      final url = Uri.parse('https://fixtures.invalid/history-cache.png');
      Widget image() =>
          harness(Center(child: ChatHistoryImage(url: url, aspectRatio: .5)));
      await tester.pumpWidget(image());
      expect(
        find.byKey(const ValueKey('chat-image-download-placeholder')),
        findsOneWidget,
      );
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(
        find.byKey(const ValueKey('chat-image-upload-overlay')),
        findsNothing,
      );
      expect(client.requests, 1);
      client.gate.complete();
      await tester.runAsync(() async {
        await precacheImage(
          NetworkImage(url.toString()),
          tester.element(find.byType(ChatHistoryImage)),
        );
      });
      await tester.pump();
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      final size = tester.getSize(find.byType(ChatHistoryImage));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(image());
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(tester.getSize(find.byType(ChatHistoryImage)), size);
      expect(client.requests, 1);
      expect(size.width / size.height, closeTo(.5, .001));
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      debugNetworkImageHttpClientProvider = null;
    },
  );

  test(
    'loaded empty cache is distinct from first load and logout erases scroll metadata',
    () async {
      final cubit = history((_) async => ChatPage([]));
      await cubit.load();
      cache.write('scroll', 123.0, prefs.sessionRevision);
      await cubit.close();
      final reopened = history((_) async => ChatPage([]));
      expect(reopened.state.hasLoaded, true);
      expect(reopened.state.items, isEmpty);
      expect(cache.read<double>('scroll'), 123.0);
      await prefs.clearSession();
      expect(cache.read<double>('scroll'), isNull);
      await reopened.close();
    },
  );
  test(
    'late response from disposed route cannot overwrite reopened history cache',
    () async {
      final initial = history((_) async => ChatPage([message]));
      await initial.load();
      await initial.close();
      final gate = Completer<ChatPage<ChatMessage>>();
      final old = history((_) => gate.future);
      final pending = old.load();
      await old.close();
      final current = history((_) async => ChatPage([message.asDeleted()]));
      await current.load();
      gate.complete(ChatPage([message]));
      await pending;
      await current.close();
      final reopened = history((_) async => ChatPage([]));
      expect(reopened.state.items.single.isDeleted, true);
      await reopened.close();
    },
  );

  testWidgets(
    'reopen reconciles older cached deletions through the retained updated_since cursor',
    (tester) async {
      final repo = ChangesRepo();
      await tester.pumpWidget(
        harness(
          Builder(
            builder: (context) => TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ConversationScreen(
                      conversation: accepted,
                      repository: repo,
                      currentUserId: 'self',
                    ),
                  ),
                );
              },
              child: const Text('Open changes'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open changes'));
      await tester.pumpAndSettle();
      expect(find.text('Older cached fixture'), findsOneWidget);
      expect(repo.cursors, isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();
      repo.messageItems =
          []; // The latest page no longer contains the older row.
      await tester.tap(find.text('Open changes'));
      await tester.pumpAndSettle();
      expect(repo.cursors, [DateTime.utc(2026, 11, 1)]);
      expect(find.text('Older cached fixture'), findsNothing);
      expect(find.text('Message deleted'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
    },
  );
}
