import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'chat_reference_ui_test.dart' show show, captureFrame, boundary;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/chats/cubit/chat_cubit.dart';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/data/chat_reachability.dart';
import 'package:travibe/features/chats/data/chat_device_media.dart';
import 'package:travibe/features/chats/data/chat_image_saver.dart';
import 'package:travibe/features/chats/screens/chats_screen.dart';
import 'package:travibe/features/chats/screens/conversation_screen.dart';
import 'package:travibe/features/chats/screens/conversation_details_screen.dart';
import 'package:travibe/features/chats/screens/chat_image_viewer.dart';
import 'package:travibe/features/chats/widgets/chat_loading.dart';
import 'package:travibe/features/chats/widgets/chat_empty_illustration.dart';
import 'package:travibe/features/chats/widgets/chat_widgets.dart';
import 'package:travibe/features/chats/widgets/chat_options.dart';
import 'package:travibe/features/chats/widgets/chat_expandable_text.dart';
import 'package:travibe/features/chats/widgets/chat_network_banner.dart';
import 'package:travibe/features/chats/widgets/chat_video_message.dart';
import 'chat_fakes.dart';
import 'chat_widgets_test.dart' show harness;
import 'message_requests_test.dart' show RequestsRepo, accepted;

ChatMessage mediaMessage(int id, {bool video = false, bool deleted = false}) =>
    ChatMessage(
      id: '$id',
      senderId: '7',
      conversationId: '42',
      kind: video ? ChatMessageKind.video : ChatMessageKind.image,
      mediaUrl: Uri.parse('https://media.invalid/$id.${video ? 'mp4' : 'png'}'),
      thumbnailUrl: video
          ? Uri.parse('https://media.invalid/$id-thumb.png')
          : null,
      isDeleted: deleted,
    );

class EdgeRepo extends RequestsRepo {
  EdgeRepo() {
    isAccepted = true;
    capabilities = const ChatCapabilities(
      list: true,
      messages: true,
      detail: true,
      read: true,
      sendText: true,
      remove: true,
      requests: true,
    );
  }
  int deletes = 0;
  bool deleted = false, failDelete = false;
  Completer<void>? deleteGate;
  @override
  Future<ChatPage<ChatConversation>> conversations({
    String? continuation,
    bool requests = false,
  }) async => ChatPage(
    requests || deleted ? [] : [accepted],
    total: requests ? 0 : null,
  );
  @override
  Future<void> remove(String id) async {
    deletes++;
    if (deleteGate != null) await deleteGate!.future;
    if (failDelete) throw ApiError(message: 'Rejected');
    deleted = true;
  }
}

class VideoDownload extends ChatDeviceMedia {
  int saves = 0;
  String? path;
  bool fail = false;
  @override
  Future<void> saveVideo(String path, String mime) async {
    this.path = path;
    expect(await File(path).exists(), true);
    expect(mime, 'video/mp4');
    if (fail) throw PlatformException(code: 'save_failed');
    saves++;
  }
}

class VideoAdapter implements HttpClientAdapter {
  String mime = 'video/mp4';
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromBytes(
    List.filled(32, 0),
    200,
    headers: {
      Headers.contentTypeHeader: [mime],
    },
  );
  @override
  void close({bool force = false}) {}
}

class ViewerSaver extends ChatImageSaver {
  final urls = <Uri>[];
  Completer<void>? gate;
  bool fail = false;
  @override
  Future<void> save(
    Uri url, {
    required CancelToken cancel,
    required bool Function() isActive,
  }) async {
    urls.add(url);
    if (gate != null) await gate!.future;
    if (fail) throw PlatformException(code: 'save_failed');
  }

  @override
  Future<void> saveVideo(
    Uri url, {
    required CancelToken cancel,
    required bool Function() isActive,
  }) => save(url, cancel: cancel, isActive: isActive);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ChatEmptyIllustration.warmUp);
  final prefs = PreferencesManager();
  setUp(() async {
    SharedPreferences.setMockInitialValues({'_token': 'fixture-session'});
    await prefs.init();
    ChatReachability.instance.reset();
  });
  tearDown(() async {
    await prefs.clear();
  });

  testWidgets('Skeletonizer uses Home dark colors, timing and reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        const Scaffold(
          body: SingleChildScrollView(child: ChatsLoadingSkeleton()),
        ),
      ),
    );
    final skeleton = tester.widget<Skeletonizer>(
      find.byWidgetPredicate((w) => w is Skeletonizer),
    );
    expect(skeleton.effect, isA<ShimmerEffect>());
    final effect = skeleton.effect! as ShimmerEffect;
    expect(effect.duration, const Duration(milliseconds: 1800));
    expect(effect.colors, contains(const Color(0xFF232323)));
    expect(effect.colors, contains(const Color(0xFF303030)));
    expect(find.byWidgetPredicate((w) => w is Bone), findsWidgets);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const Scaffold(body: ChatHistorySkeleton()),
        ),
      ),
    );
    expect(
      tester
          .widget<Skeletonizer>(
            find.byWidgetPredicate((w) => w is Skeletonizer),
          )
          .effect,
      isA<SolidColorEffect>(),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'confirmed empty Inbox uses original illustration and retains header/search',
    (tester) async {
      final repo = FakeChatRepository()..items = [];
      await tester.pumpWidget(harness(ChatsScreen(repository: repo)));
      await tester.pumpAndSettle();
      expect(find.text('No messages yet'), findsOneWidget);
      expect(
        find.text(
          'Start a conversation with someone and your chats will appear here.',
        ),
        findsOneWidget,
      );
      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('Requests'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(ChatEmptyIllustration), findsOneWidget);
      expect(
        tester.getSize(find.byType(ChatEmptyIllustration)),
        const Size(134, 121),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('pending or failed Inbox never masquerades as confirmed empty', (
    tester,
  ) async {
    final repo = FakeChatRepository()..loading = Completer();
    await tester.pumpWidget(harness(ChatsScreen(repository: repo)));
    await tester.pump();
    expect(find.byType(ChatsLoadingSkeleton), findsOneWidget);
    expect(find.text('No messages yet'), findsNothing);
    repo.loading!.completeError(ApiError(message: 'Offline request failed'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Offline request failed'), findsOneWidget);
    expect(find.textContaining("Couldn't load chats"), findsOneWidget);
    expect(find.text('No messages yet'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'options sheet has four actions and returns selection without mutation',
    (tester) async {
      ChatOption? selected;
      await tester.pumpWidget(
        harness(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  selected = await showModalBottomSheet<ChatOption>(
                    context: context,
                    builder: (_) => const ChatOptionsSheet(),
                  );
                },
                child: const Text('Options'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Options'));
      await tester.pumpAndSettle();
      for (final title in [
        'View user profile',
        'Delete chat',
        'Report',
        'Block user',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.byType(SvgPicture), findsNWidgets(4));
      await tester.tap(find.text('View user profile'));
      await tester.pumpAndSettle();
      expect(selected, ChatOption.profile);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Delete cancellation preserves conversation; success locks requests and removes Inbox row',
    (tester) async {
      final repo = EdgeRepo()..deleteGate = Completer();
      await tester.pumpWidget(harness(ChatsScreen(repository: repo)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Request Person'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Conversation options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete chat'));
      await tester.pumpAndSettle();
      expect(find.text('Delete chat?'), findsOneWidget);
      expect(
        find.text('This will remove the chat from your messages.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.deletes, 0);
      await tester.tap(find.byTooltip('Conversation options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete chat'));
      await tester.pumpAndSettle();
      final button = find.widgetWithText(TextButton, 'Delete');
      final position = tester.getCenter(button);
      await tester.tapAt(position);
      await tester.pump();
      await tester.tapAt(position);
      await tester.pump();
      expect(repo.deletes, 1);
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(repo.deleted, false);
      repo.deleteGate!.complete();
      await tester.pumpAndSettle();
      expect(repo.deleted, true);
      expect(find.byType(ConversationScreen), findsNothing);
      expect(find.text('No messages yet'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Delete API failure preserves open conversation and allows explicit retry',
    (tester) async {
      final repo = EdgeRepo()..failDelete = true;
      await tester.pumpWidget(
        harness(ConversationScreen(conversation: accepted, repository: repo)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Conversation options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete chat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(repo.deleted, false);
      expect(repo.deletes, 1);
      expect(
        find.text('Unable to delete chat. Please try again.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(ConversationScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'failed text is retained, retry targets original text and locks duplicate sends',
    () async {
      final repo = FakeChatRepository()
        ..failure = ApiError(message: 'Rejected', statusCode: 422);
      final sent = <ChatMessage>[];
      final composer = ChatComposerCubit(
        repository: repo,
        conversation: conversation,
        onSent: sent.add,
      );
      composer.edit('Original 🌴\nDraft');
      await composer.send();
      expect(composer.state.localMessages.single.delivery, ChatDelivery.failed);
      final id = composer.state.localMessages.single.id;
      expect(composer.retryNeedsConfirmation(id), false);
      composer.edit('Next draft');
      repo.failure = null;
      repo.sending = Completer();
      final retry = composer.retry(id);
      await composer.retry(id);
      expect(repo.sends, 2);
      expect(
        composer.state.localMessages.single.delivery,
        ChatDelivery.sending,
      );
      repo.sending!.complete(message);
      await retry;
      expect(sent, [message]);
      expect(composer.state.localMessages, isEmpty);
      expect(composer.state.draft, 'Next draft');
      await composer.close();
    },
  );
  test(
    'ambiguous send needs confirmation and account switch removes local private state',
    () async {
      final repo = FakeChatRepository()..failure = TimeoutException('Timeout');
      final composer = ChatComposerCubit(
        repository: repo,
        conversation: conversation,
        onSent: (_) {},
      );
      composer.edit('Private failed draft');
      await composer.send();
      expect(
        composer.retryNeedsConfirmation(composer.state.localMessages.single.id),
        true,
      );
      await prefs.saveToken('new-account');
      expect(composer.state.localMessages, isEmpty);
      expect(composer.state.draft, isEmpty);
      await composer.close();
    },
  );
  testWidgets(
    'failed bubble has no fabricated receipt and retries only via action',
    (tester) async {
      int retries = 0;
      await tester.pumpWidget(
        harness(
          Scaffold(
            body: ChatMessageBubble(
              message: const ChatMessage(
                id: 'local-1',
                senderId: '',
                kind: ChatMessageKind.text,
                text: 'Failed message',
                delivery: ChatDelivery.failed,
              ),
              outgoing: true,
              detailsExpanded: true,
              onRetry: () => retries++,
            ),
          ),
        ),
      );
      expect(find.text('Failed to send. Tap to retry.'), findsOneWidget);
      expect(find.textContaining('Seen'), findsNothing);
      expect(find.text('Sent'), findsNothing);
      await tester.tap(find.text('Failed to send. Tap to retry.'));
      expect(retries, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final width in [320.0, 375.0, 393.0, 430.0]) {
    testWidgets(
      'long multiline/RTL message expands without overflow at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final text = List.filled(
          25,
          'مرحبا 🌍 This is a long message.\n',
        ).join();
        await tester.pumpWidget(
          harness(
            Scaffold(
              body: SingleChildScrollView(
                child: ChatMessageBubble(
                  message: ChatMessage(
                    id: 'long',
                    senderId: '7',
                    kind: ChatMessageKind.text,
                    text: text,
                  ),
                  outgoing: false,
                ),
              ),
            ),
            scale: 1.6,
            direction: TextDirection.rtl,
          ),
        );
        expect(find.text('Read More...'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Read More...'));
        await tester.pumpAndSettle();
        expect(find.text('Read Less'), findsOneWidget);
        expect(find.byType(SelectionArea), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Read Less'));
        await tester.tap(find.text('Read Less'));
        await tester.pumpAndSettle();
        expect(find.text('Read More...'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('short message has no expansion action', (tester) async {
    await tester.pumpWidget(
      harness(
        const Scaffold(
          body: ChatExpandableText(text: 'Short message', messageId: 'short'),
        ),
      ),
    );
    expect(find.text('Read More...'), findsNothing);
  });

  testWidgets(
    'confirmed offline banner reconnects once and stops checks after disposal',
    (tester) async {
      bool? connected = false;
      int checks = 0, reconnects = 0;
      await tester.pumpWidget(
        harness(
          Scaffold(
            body: ChatNetworkBanner(
              status: () async {
                checks++;
                return connected;
              },
              onReconnect: () async {
                reconnects++;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No internet connection'), findsOneWidget);
      connected = true;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('No internet connection'), findsNothing);
      expect(reconnects, 1);
      await tester.pumpWidget(const SizedBox());
      final last = checks;
      await tester.pump(const Duration(seconds: 10));
      expect(checks, last);
    },
  );
  testWidgets(
    'API reachability clears a stale offline report and reconnects once',
    (tester) async {
      final reachability = ChatReachability();
      int reconnects = 0;
      await tester.pumpWidget(
        harness(
          Scaffold(
            body: ChatNetworkBanner(
              reachability: reachability,
              status: () async => false,
              onReconnect: () async {
                reconnects++;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No internet connection'), findsOneWidget);
      reachability.markReachable();
      await tester.pumpAndSettle();
      expect(find.text('No internet connection'), findsNothing);
      expect(reconnects, 1);
      // The interface keeps reporting false, but the recent response wins.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('No internet connection'), findsNothing);
      expect(reconnects, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'offline banner probes reconnect every third check without overlap',
    (tester) async {
      int probes = 0;
      final gate = Completer<void>();
      await tester.pumpWidget(
        harness(
          Scaffold(
            body: ChatNetworkBanner(
              reachability: ChatReachability(),
              status: () async => false,
              onReconnect: () {
                probes++;
                return gate.future;
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(probes, 0);
      await tester.pump(const Duration(seconds: 10));
      expect(probes, 1);
      // The first probe is still pending: later ticks must not start another.
      await tester.pump(const Duration(seconds: 15));
      expect(probes, 1);
      gate.complete();
      await tester.pump(const Duration(seconds: 15));
      expect(probes, 2);
      expect(find.text('No internet connection'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'unknown connectivity and disposed pending checks never report offline',
    (tester) async {
      final gate = Completer<bool?>();
      await tester.pumpWidget(
        harness(Scaffold(body: ChatNetworkBanner(status: () => gate.future))),
      );
      await tester.pump();
      expect(find.text('No internet connection'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      gate.complete(false);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shared gallery uses borrowed pagination, excludes deleted/audio and opens media viewer',
    (tester) async {
      int calls = 0;
      final gallery = ChatListCubit<ChatMessage>(
        fetch: (next) async {
          calls++;
          return next == null
              ? ChatPage([
                  mediaMessage(1),
                  mediaMessage(2, video: true),
                  mediaMessage(3, deleted: true),
                ], continuation: '2')
              : ChatPage([mediaMessage(4)]);
        },
        idOf: (m) => m.id,
        cancel: () {},
      );
      await gallery.load();
      await tester.pumpWidget(
        harness(
          ConversationDetailsScreen(conversation: accepted, messages: gallery),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('shared-media-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('shared-media-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('shared-media-3')), findsNothing);
      expect(find.text('Showing media from loaded history.'), findsOneWidget);
      await tester.ensureVisible(find.text('Load older media'));
      await tester.tap(find.text('Load older media'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.byKey(const ValueKey('shared-media-4')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('shared-media-4')));
      await tester.tap(find.byKey(const ValueKey('shared-media-4')));
      await tester.pumpAndSettle();
      expect(find.byType(ChatImageViewer), findsOneWidget);
      expect(find.text('Media'), findsOneWidget);
      await prefs.saveToken('other-account');
      await tester.pumpAndSettle();
      expect(find.text('Sign in again to view this image.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await gallery.close();
    },
  );
  testWidgets(
    'header name opens details while avatar retains profile affordance',
    (tester) async {
      final repo = EdgeRepo();
      await tester.pumpWidget(
        harness(ConversationScreen(conversation: accepted, repository: repo)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Request Person'));
      await tester.pumpAndSettle();
      expect(find.byType(ConversationDetailsScreen), findsOneWidget);
      expect(find.text('User Profile'), findsOneWidget);
      expect(find.text('Report'), findsOneWidget);
      expect(find.text('Block User'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'media viewer thumbnails synchronize selection and save result is authoritative',
    (tester) async {
      final saver = ViewerSaver()..gate = Completer();
      final media = [mediaMessage(1), mediaMessage(2, video: true)];
      await tester.pumpWidget(
        harness(
          ChatImageViewer(
            url: media.first.mediaUrl!,
            media: media,
            saver: saver,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('media-thumbnail-1')));
      await tester.pumpAndSettle();
      expect(find.byType(ChatVideoMessage), findsOneWidget);
      await tester.tap(find.byTooltip('Save video to gallery'));
      await tester.pump();
      expect(saver.urls, [media[1].mediaUrl]);
      expect(find.text('Video Saved to Gallery'), findsNothing);
      saver.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Video Saved to Gallery'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      saver.dispose();
    },
  );
  for (final failure in [false, true]) {
    test(
      'video download streams to a private file, propagates save result and cleans up; failure=$failure',
      () async {
        final bridge = VideoDownload()..fail = failure;
        final dio = Dio()..httpClientAdapter = VideoAdapter();
        final saver = ChatImageSaver(dio: dio, device: bridge);
        final operation = saver.saveVideo(
          Uri.parse('https://media.invalid/video.mp4'),
          cancel: CancelToken(),
          isActive: () => true,
        );
        if (failure) {
          await expectLater(operation, throwsA(isA<PlatformException>()));
        } else {
          await operation;
        }
        expect(bridge.saves, failure ? 0 : 1);
        expect(await File(bridge.path!).exists(), false);
        saver.dispose();
      },
    );
  }
  test(
    'unsupported download MIME and invalid URLs never invoke gallery bridge',
    () async {
      final bridge = VideoDownload(),
          adapter = VideoAdapter()..mime = 'text/html';
      final saver = ChatImageSaver(
        dio: Dio()..httpClientAdapter = adapter,
        device: bridge,
      );
      await expectLater(
        saver.saveVideo(
          Uri.parse('https://media.invalid/video'),
          cancel: CancelToken(),
          isActive: () => true,
        ),
        throwsFormatException,
      );
      expect(bridge.saves, 0);
      await expectLater(
        saver.saveVideo(
          Uri.parse('https://user:secret@media.invalid/video'),
          cancel: CancelToken(),
          isActive: () => true,
        ),
        throwsFormatException,
      );
      saver.dispose();
    },
  );
  test(
    'confirmed hidden-thread removal ignores old responses but permits later REST restoration',
    () async {
      Completer<ChatPage<ChatConversation>>? gate;
      final list = ChatListCubit<ChatConversation>(
        fetch: (_) => gate?.future ?? Future.value(ChatPage([accepted])),
        idOf: (c) => c.id,
        cancel: () {},
      );
      await list.load();
      gate = Completer();
      final old = list.load();
      list.removeConfirmed(
        '42',
        session: prefs.sessionRevision,
        allowRestoration: true,
      );
      expect(list.state.items, isEmpty);
      expect(list.state.loading, false);
      gate.complete(ChatPage([accepted]));
      await old;
      expect(list.state.items, isEmpty);
      gate = null;
      await list.load();
      expect(list.state.items.single.id, '42');
      await list.close();
    },
  );
  test(
    'late successful send after account switching cannot restore the old outbox',
    () async {
      final repo = FakeChatRepository()..sending = Completer();
      final sent = <ChatMessage>[];
      final composer = ChatComposerCubit(
        repository: repo,
        conversation: conversation,
        onSent: sent.add,
      );
      composer.edit('Old account draft');
      final operation = composer.send();
      await prefs.saveToken('replacement');
      repo.sending!.complete(message);
      await operation;
      expect(sent, isEmpty);
      expect(composer.state.localMessages, isEmpty);
      expect(composer.state.draft, isEmpty);
      await composer.close();
    },
  );
  testWidgets(
    'gallery initial loading, failed history and retry preserve the correct state',
    (tester) async {
      final gate = Completer<ChatPage<ChatMessage>>();
      bool fail = true;
      final list = ChatListCubit<ChatMessage>(
        fetch: (_) async {
          if (fail) return gate.future;
          return ChatPage([]);
        },
        idOf: (m) => m.id,
        cancel: () {},
      );
      final operation = list.load();
      await tester.pumpWidget(
        harness(
          ConversationDetailsScreen(conversation: accepted, messages: list),
        ),
      );
      await tester.pump();
      expect(find.byType(ChatMediaSkeleton), findsOneWidget);
      expect(find.text('No shared media in loaded history.'), findsNothing);
      gate.completeError(ApiError(message: 'History failed'));
      await operation;
      await tester.pumpAndSettle();
      expect(find.text('History failed'), findsOneWidget);
      expect(find.byType(ChatMediaSkeleton), findsNothing);
      fail = false;
      await tester.ensureVisible(find.text('Retry'));
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('No shared media in loaded history.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await list.close();
    },
  );
  testWidgets(
    'viewer save failure never announces success and does not duplicate pending saves',
    (tester) async {
      final saver = ViewerSaver()
        ..gate = Completer()
        ..fail = true;
      await tester.pumpWidget(
        harness(
          ChatImageViewer(
            url: Uri.parse('https://media.invalid/photo.png'),
            saver: saver,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final target = tester.getCenter(find.byTooltip('Save image to gallery'));
      await tester.tapAt(target);
      await tester.pump();
      await tester.tapAt(target);
      await tester.pump();
      expect(saver.urls, hasLength(1));
      saver.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Image Saved to Gallery'), findsNothing);
      expect(find.textContaining('Unable to save image.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      saver.dispose();
    },
  );
  testWidgets(
    'session switch closes Delete dialog without applying a late mutation to Inbox',
    (tester) async {
      final repo = EdgeRepo()..deleteGate = Completer();
      int removals = 0;
      await tester.pumpWidget(
        harness(
          ConversationScreen(
            conversation: accepted,
            repository: repo,
            onDeleted: () => removals++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Conversation options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete chat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pump();
      await prefs.saveToken('replacement');
      await tester.pumpAndSettle();
      expect(find.text('Delete chat?'), findsNothing);
      expect(find.text('Sign in again to use messaging.'), findsOneWidget);
      repo.deleteGate!.complete();
      await tester.pumpAndSettle();
      expect(removals, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Delete cannot race an in-flight text send', (tester) async {
    final repo = EdgeRepo()..sending = Completer();
    await tester.pumpWidget(
      harness(ConversationScreen(conversation: accepted, repository: repo)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Pending draft');
    await tester.pump();
    await tester.tap(find.byTooltip('Send message'));
    await tester.pump();
    await tester.tap(find.byTooltip('Conversation options'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Delete chat'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(repo.deletes, 0);
    expect(find.text('Delete chat?'), findsNothing);
    expect(
      find.text(
        'Finish or cancel the current send or attachment before deleting this chat.',
      ),
      findsOneWidget,
    );
    repo.sending!.complete(
      const ChatMessage(
        id: '102',
        senderId: '5',
        conversationId: '42',
        kind: ChatMessageKind.text,
        text: 'Pending draft',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ConversationScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('supplied illustration paints its original embedded artwork', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    await show(
      tester,
      const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: ChatEmptyIllustration()),
      ),
    );
    await tester.runAsync(
      () => ChatEmptyIllustration.precache(
        tester.element(find.byType(ChatEmptyIllustration)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await render.toImage();
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      var orange = 0;
      for (var i = 0; i < pixels.lengthInBytes; i += 4) {
        if (pixels.getUint8(i) > 180 &&
            pixels.getUint8(i + 1) > 50 &&
            pixels.getUint8(i + 2) < 100) {
          orange++;
        }
      }
      image.dispose();
      expect(orange, greaterThan(100));
    });
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('render enhanced states with real theme and no production data', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    if (const bool.fromEnvironment('CHAT_CAPTURE')) {
      await tester.runAsync(() async {
        final font = FontLoader(
          'Plus Jakarta Sans',
        )..addFont(rootBundle.load('assets/fonts/PlusJakartaSans-Regular.ttf'));
        await font.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
      });
    }
    final empty = FakeChatRepository()..items = [];
    await show(tester, ChatsScreen(repository: empty));
    await tester.pumpAndSettle();
    expect(find.text('No messages yet'), findsOneWidget);
    if (const bool.fromEnvironment('CHAT_CAPTURE')) {
      await tester.runAsync(
        () => ChatEmptyIllustration.precache(
          tester.element(find.byType(ChatEmptyIllustration)),
        ),
      );
      await tester.pumpAndSettle();
    }
    await captureFrame(tester, 'edge-empty');
    final repo = EdgeRepo();
    await show(
      tester,
      ConversationScreen(conversation: accepted, repository: repo),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Conversation options'));
    await tester.pumpAndSettle();
    await captureFrame(tester, 'edge-options');
    await tester.tap(find.text('Delete chat'));
    await tester.pumpAndSettle();
    await captureFrame(tester, 'edge-delete');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request Person'));
    await tester.pumpAndSettle();
    await captureFrame(tester, 'edge-details');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await show(
      tester,
      ChatImageViewer(
        url: mediaMessage(1).mediaUrl!,
        media: [mediaMessage(1), mediaMessage(2, video: true)],
      ),
    );
    await tester.pumpAndSettle();
    await captureFrame(tester, 'edge-viewer');
    final text = List.filled(
      20,
      'A long travel message with line breaks. 🌴\n',
    ).join();
    await show(
      tester,
      Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                ChatMessageBubble(
                  message: ChatMessage(
                    id: 'long-render',
                    senderId: '7',
                    kind: ChatMessageKind.text,
                    text: text,
                  ),
                  outgoing: false,
                ),
                ChatMessageBubble(
                  message: const ChatMessage(
                    id: 'failed-render',
                    senderId: '7',
                    kind: ChatMessageKind.text,
                    text: 'Unsent draft',
                    delivery: ChatDelivery.failed,
                  ),
                  outgoing: true,
                  onRetry: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Read More...'), findsOneWidget);
    await captureFrame(tester, 'edge-long');
    await show(
      tester,
      Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              ChatNetworkBanner(status: () async => false),
              const Expanded(
                child: Center(child: Text('Cached conversation history')),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No internet connection'), findsOneWidget);
    await captureFrame(tester, 'edge-offline');
    await tester.pumpWidget(const SizedBox());
  });
}
