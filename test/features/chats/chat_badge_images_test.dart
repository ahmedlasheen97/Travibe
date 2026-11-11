import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:travibe/features/chats/screens/chat_image_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:travibe/core/media/media_upload_service.dart';
import 'chat_media_queue_send_test.dart' show UploadFake, MediaRepositoryFake;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/chats/cubit/chat_unread_cubit.dart';
import 'package:travibe/features/chats/cubit/chat_cubit.dart';
import 'package:travibe/features/chats/cubit/chat_audio_controller.dart';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/data/chat_reverb_service.dart';
import 'package:travibe/features/chats/data/chat_media_selection.dart';
import 'package:travibe/features/chats/screens/conversation_screen.dart';
import 'package:travibe/features/chats/widgets/chat_reverb_host.dart';
import 'package:travibe/features/chats/widgets/chat_send_button.dart';
import 'package:travibe/features/chats/widgets/chat_composer.dart';
import 'package:travibe/features/chats/widgets/chat_selected_media_tray.dart';
import 'package:travibe/features/chats/widgets/chat_pending_media_bubble.dart';
import 'package:travibe/features/chats/widgets/chat_widgets.dart';
import 'package:travibe/features/home/widgets/home_top_bar.dart';
import '../chats/chat_fakes.dart';
import 'chat_interactions_test.dart' show png;
import 'chat_loading_lifecycle_test.dart' show ImageClient;
import 'chat_widgets_test.dart' show harness;
import 'message_requests_test.dart' show RequestsRepo, RequestsReverb, accepted;
import '../../core/notifications/push_notifications_host_test.dart'
    show ControlledCurrentUser;
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';

ChatConversation thread(String id, int unread) => ChatConversation(
  id: id,
  participant: participant,
  unread: unread,
  isAccepted: true,
  isBlocked: false,
);

class UnreadRepo extends FakeChatRepository {
  final pages = <String, ChatPage<ChatConversation>>{};
  final calls = <String>[];
  Completer<void>? gate;
  @override
  Future<ChatPage<ChatConversation>> conversations({
    String? continuation,
    bool requests = false,
  }) async {
    final key = '${requests ? 'requests' : 'inbox'}:${continuation ?? 'first'}';
    calls.add(key);
    final page = pages[key] ?? ChatPage<ChatConversation>([]);
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    return page;
  }
}

class ReaderRepo extends RequestsRepo {
  ReaderRepo(this.unread) {
    isAccepted = true;
  }
  final UnreadRepo unread;
  bool failRead = false;
  @override
  Future<ChatConversation> readConversation(String id) async {
    reads++;
    if (failRead) throw ApiError(message: 'Read rejected');
    unread.pages['inbox:first'] = ChatPage([thread('42', 0)]);
    return accepted;
  }
}

class WaitingImageUpload extends UploadFake {
  final gate = Completer<void>();
  @override
  Future<int> upload({
    required String filename,
    required String contentType,
    required Uint8List bytes,
    required bool Function() isActive,
    required CancelToken cancelToken,
    required void Function(MediaUploadStage) onStage,
    void Function(int, int)? onProgress,
  }) async {
    uploads++;
    onStage(MediaUploadStage.uploading);
    onProgress?.call(1, 2);
    await gate.future;
    if (cancelToken.isCancelled || !isActive()) throw StateError('Cancelled');
    return 101;
  }
}

Future<void> drain() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.microtask(() {});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List portrait;
  setUpAll(() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 24, 48),
      ui.Paint()..color = const Color(0xFF6C7580),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(24, 48);
    portrait = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
  });
  final prefs = PreferencesManager();
  late UnreadRepo repo;
  late ChatUnreadCubit unread;
  final owner = Object();
  setUp(() async {
    SharedPreferences.setMockInitialValues({'_token': 'fixture-account'});
    await prefs.init();
    repo = UnreadRepo();
    unread = ChatUnreadCubit(
      repository: repo,
      reconcileInterval: Duration.zero,
    );
  });
  tearDown(() async {
    if (!unread.isClosed) await unread.close();
    await prefs.clear();
  });
  Future<void> start() async {
    unread.account('5');
    unread.attach(owner);
    await drain();
  }

  test(
    'badge requires eligible Root and a verified account; merely attaching does not invent unread',
    () async {
      unread.attach(owner);
      await drain();
      expect(repo.calls, isEmpty);
      expect(unread.state.hasUnread, false);
      unread.account('5');
      await drain();
      expect(repo.calls, ['inbox:first', 'requests:first']);
      expect(unread.state.confirmed, true);
      expect(unread.state.hasUnread, false);
    },
  );
  test(
    'server unread survives Home reattach and clears only after authoritative zero',
    () async {
      repo.pages['inbox:first'] = ChatPage([thread('42', 3)]);
      await start();
      expect(unread.state.hasUnread, true);
      final calls = repo.calls.length;
      unread.attach(owner);
      await drain();
      expect(repo.calls.length, calls);
      expect(unread.state.hasUnread, true);
      await unread.refresh();
      expect(unread.state.hasUnread, true);
      repo.pages['inbox:first'] = ChatPage([thread('42', 0)]);
      await unread.refresh();
      expect(unread.state.hasUnread, false);
    },
  );
  test(
    'pending requests and later pages contribute actual unread; no inferred outgoing count',
    () async {
      repo.pages['inbox:first'] = ChatPage([thread('1', 0)], continuation: '2');
      repo.pages['inbox:2'] = ChatPage([thread('2', 0)]);
      repo.pages['requests:first'] = ChatPage([
        thread('3', 0),
      ], continuation: '2');
      repo.pages['requests:2'] = ChatPage([thread('4', 1)]);
      await start();
      expect(unread.state.hasUnread, true);
      expect(repo.calls, [
        'inbox:first',
        'requests:first',
        'inbox:2',
        'requests:2',
      ]);
      repo.pages['requests:2'] = ChatPage([thread('4', 0)]);
      await unread.refresh();
      expect(unread.state.hasUnread, false);
    },
  );
  test(
    'network and partial/cyclic pagination failures retain last confirmed indicator',
    () async {
      repo.pages['inbox:first'] = ChatPage([thread('42', 1)]);
      await start();
      repo.failure = ApiError(message: 'Unavailable');
      await unread.refresh();
      expect(unread.state.hasUnread, true);
      expect(unread.state.error, true);
      repo.failure = null;
      repo.pages['inbox:first'] = ChatPage([], continuation: 'same');
      repo.pages['inbox:same'] = ChatPage([], continuation: 'same');
      await unread.refresh();
      expect(unread.state.hasUnread, true);
      expect(unread.state.error, true);
    },
  );
  test('bounded incomplete scan never falsely confirms zero', () async {
    await unread.close();
    unread = ChatUnreadCubit(
      repository: repo,
      maxPages: 2,
      reconcileInterval: Duration.zero,
    );
    repo.pages['inbox:first'] = ChatPage([thread('42', 1)]);
    await start();
    repo.pages['inbox:first'] = ChatPage([], continuation: '2');
    await unread.refresh();
    expect(unread.state.hasUnread, true);
    expect(unread.state.error, true);
  });
  test('missing unread_count is unknown, not a fabricated zero', () async {
    repo.pages['inbox:first'] = ChatPage([thread('42', 1)]);
    await start();
    final incomplete = ChatConversation.fromJson({
      'id': 42,
      'other_user': {'id': 7, 'name': 'Fixture'},
      'unread_count': null,
    });
    expect(incomplete.hasUnreadCount, false);
    expect(incomplete.withSending(true).hasUnreadCount, false);
    repo.pages['inbox:first'] = ChatPage([incomplete]);
    await unread.refresh();
    expect(unread.state.hasUnread, true);
    expect(unread.state.error, true);
  });
  test(
    'in-flight stale unread result cannot overwrite later read reconciliation',
    () async {
      repo.pages['inbox:first'] = ChatPage([thread('42', 2)]);
      await start();
      repo.gate = Completer();
      final old = unread.refresh();
      repo.pages['inbox:first'] = ChatPage([thread('42', 0)]);
      final latest = unread.refresh();
      repo.gate!.complete();
      await Future.wait([old, latest]);
      expect(unread.state.hasUnread, false);
      expect(unread.state.confirmed, true);
    },
  );
  test(
    'logout/account switching discard old results and require fresh identity',
    () async {
      repo.pages['inbox:first'] = ChatPage([thread('42', 5)]);
      repo.gate = Completer();
      unread.account('5');
      unread.attach(owner);
      final oldGate = repo.gate!;
      await prefs.saveToken('replacement-account');
      expect(unread.state.hasUnread, false);
      repo.gate = null;
      repo.pages['inbox:first'] = ChatPage([thread('99', 0)]);
      unread.account('9');
      await drain();
      oldGate.complete();
      await drain();
      expect(unread.state.session, prefs.sessionRevision);
      expect(unread.state.hasUnread, false);
      await prefs.clearSession();
      expect(unread.state.hasUnread, false);
    },
  );

  testWidgets(
    'Home renders numeric server unread badge; taps do not clear it or alter notification badge',
    (tester) async {
      final reverb = RequestsReverb();
      repo.pages['inbox:first'] = ChatPage([thread('42', 1)]);
      await start();
      int opens = 0;
      await tester.pumpWidget(
        ChatReverbScope(
          service: reverb,
          unread: unread,
          child: harness(
            Scaffold(
              body: HomeTopBar(
                unreadCount: 4,
                onMessagesTap: () => opens++,
                onNotificationsTap: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-unread-badge')), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home-messages-button')));
      await tester.pumpAndSettle();
      expect(opens, 1);
      expect(unread.state.hasUnread, true);
      repo.pages['inbox:first'] = ChatPage([thread('42', 0)]);
      await unread.refresh();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-unread-badge')), findsNothing);
      expect(find.text('4'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      reverb.dispose();
    },
  );
  for (final fail in [false, true]) {
    testWidgets('confirmed read refreshes Home badge; failure=$fail', (
      tester,
    ) async {
      final reverb = RequestsReverb();
      repo.pages['inbox:first'] = ChatPage([thread('42', 1)]);
      await start();
      final reader = ReaderRepo(repo)..failRead = fail;
      await tester.pumpWidget(
        ChatReverbScope(
          service: reverb,
          unread: unread,
          child: harness(
            Builder(
              builder: (context) => Scaffold(
                body: HomeTopBar(
                  onMessagesTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ConversationScreen(
                        conversation: accepted,
                        repository: reader,
                      ),
                    ),
                  ),
                  onNotificationsTap: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-messages-button')));
      await tester.pumpAndSettle();
      expect(reader.reads, greaterThan(0));
      expect(unread.state.hasUnread, fail);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat-unread-badge')),
        fail ? findsOneWidget : findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      reverb.dispose();
    });
  }
  testWidgets(
    'Reverb hints reconcile through REST, coalesce duplicates and ignore old sessions',
    (tester) async {
      final user = ControlledCurrentUser()..confirm('5'),
          service = RequestsReverb();
      unread.attach(owner);
      await tester.pumpWidget(
        BlocProvider<CurrentUserCubit>.value(
          value: user,
          child: ChatReverbHost(
            service: service,
            unread: unread,
            child: harness(
              Scaffold(
                body: HomeTopBar(
                  onMessagesTap: () {},
                  onNotificationsTap: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(unread.state.hasUnread, false);
      repo.pages['requests:first'] = ChatPage([thread('42', 7)]);
      final before = repo.calls.length;
      for (var i = 0; i < 5; i++) {
        service.hints.add(
          ChatReverbSignal(
            i.isEven ? 'message.sent' : 'notification.created',
            prefs.sessionRevision,
          ),
        );
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-unread-badge')), findsOneWidget);
      expect(repo.calls.length - before, 2);
      expect(unread.state.count, 7);
      expect(find.text('7'), findsOneWidget);
      repo.pages['requests:first'] = ChatPage([]);
      service.hints.add(
        ChatReverbSignal('notifications.read_all', prefs.sessionRevision - 1),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(unread.state.hasUnread, true);
      expect(unread.state.count, 7);
      service.hints.add(ChatReverbSignal('reconcile', prefs.sessionRevision));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(unread.state.hasUnread, false);
      expect(unread.state.count, 0);
      await tester.pumpWidget(const SizedBox());
      await user.close();
      service.dispose();
    },
  );
  testWidgets(
    'resume and foreground fallback reconcile without clearing on Home open',
    (tester) async {
      await unread.close();
      unread = ChatUnreadCubit(
        repository: repo,
        reconcileInterval: const Duration(seconds: 45),
      );
      await tester.pumpWidget(harness(const Scaffold()));
      unread.account('5');
      unread.attach(owner);
      await tester.pumpAndSettle();
      repo.pages['inbox:first'] = ChatPage([thread('42', 1)]);
      await tester.pump(const Duration(seconds: 45));
      await tester.pumpAndSettle();
      expect(unread.state.hasUnread, true);
      unread.foreground(false);
      final calls = repo.calls.length;
      await tester.pump(const Duration(seconds: 90));
      expect(repo.calls.length, calls);
      repo.pages['inbox:first'] = ChatPage([]);
      unread.foreground(true);
      await tester.pumpAndSettle();
      expect(unread.state.hasUnread, false);
      await tester.pumpWidget(const SizedBox());
      await unread.close();
    },
  );

  for (final width in [320.0, 375.0, 393.0, 430.0]) {
    testWidgets(
      'one Send button uses same SVG for text/attachments and preserves removal at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final composer = ChatComposerCubit(
              repository: FakeChatRepository(),
              conversation: conversation,
              onSent: (_) {},
            ),
            audio = ChatAudioController(recordingSupported: false),
            text = TextEditingController();
        final item = ChatMediaSelection(
          png,
          'fixture.png',
          'image/png',
          ChatMessageKind.image,
        );
        int sends = 0, removed = 0;
        Widget screen(bool selected) => harness(
          Scaffold(
            body: Column(
              children: [
                const Expanded(child: SizedBox()),
                ChatComposer(
                  composer: composer,
                  text: text,
                  audio: audio,
                  canSend: true,
                  uploading: false,
                  onAttachment: () {},
                  onTyped: () {},
                  onSendVoice: () {},
                  onDiscardMedia: () {},
                  onSendAttachments: () => sends++,
                  selectedMediaTray: selected
                      ? ChatSelectedMediaTray(
                          items: [item],
                          onRemove: (_) => removed++,
                          onSend: () => sends++,
                          showSendButton: false,
                        )
                      : null,
                ),
              ],
            ),
          ),
        );
        composer.edit('Caption');
        text.text = 'Caption';
        await tester.pumpWidget(screen(false));
        await tester.pumpAndSettle();
        expect(find.byType(ChatSendButton), findsOneWidget);
        expect(tester.getSize(find.byType(ChatSendButton)), const Size(48, 48));
        await tester.pumpWidget(screen(true));
        await tester.pumpAndSettle();
        expect(find.byType(ChatSendButton), findsOneWidget);
        final svg = find.descendant(
          of: find.byType(ChatSendButton),
          matching: find.byType(SvgPicture),
        );
        expect(svg, findsOneWidget);
        expect(tester.getSize(svg), const Size(20, 20));
        await tester.tap(find.byTooltip('Remove selected attachment 1'));
        expect(removed, 1);
        await tester.tap(find.byTooltip('Send attachments'));
        expect(sends, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        audio.dispose();
        text.dispose();
        await composer.close();
      },
    );
  }
  for (final reduced in [false, true]) {
    testWidgets(
      'pending image shows muted Sending… label (no spinner) and retry; reduced=$reduced',
      (tester) async {
        final item = ChatMediaSelection(
          png,
          'fixture.png',
          'image/png',
          ChatMessageKind.image,
        );
        int retries = 0;
        Widget screen(bool sending) => harness(
          MediaQuery(
            data: MediaQueryData(
              size: const Size(390, 844),
              disableAnimations: reduced,
            ),
            child: Scaffold(
              body: ChatPendingMediaBubble(
                media: item,
                sending: sending,
                onRetry: () => retries++,
              ),
            ),
          ),
        );
        await tester.pumpWidget(screen(true));
        await tester.pump();
        expect(find.byType(CupertinoActivityIndicator), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.text('Sending…'), findsOneWidget);
        expect(find.text('Failed to send. Tap to retry.'), findsNothing);
        expect(find.byType(Image), findsOneWidget);
        await tester.tap(find.text('Sending…'));
        expect(retries, 0);
        await tester.pumpWidget(screen(false));
        await tester.pumpAndSettle();
        expect(find.text('Sending…'), findsNothing);
        await tester.tap(find.text('Failed to send. Tap to retry.'));
        expect(retries, 1);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'confirmed images have zero padding/transparent background; text colors remain',
    (tester) async {
      for (final outgoing in [false, true]) {
        await tester.pumpWidget(
          harness(
            Scaffold(
              body: ChatMessageBubble(
                message: ChatMessage(
                  id: 'image',
                  senderId: '7',
                  kind: ChatMessageKind.image,
                  mediaUrl: Uri.parse('https://fixtures.invalid/image.png'),
                ),
                outgoing: outgoing,
              ),
            ),
          ),
        );
        final containers = tester.widgetList<Container>(
          find.descendant(
            of: find.byType(ChatMessageBubble),
            matching: find.byType(Container),
          ),
        );
        final surface = containers.firstWhere(
          (c) => c.decoration is BoxDecoration,
        );
        expect(
          (surface.decoration! as BoxDecoration).color,
          Colors.transparent,
        );
        expect(surface.padding, EdgeInsets.zero);
        await tester.pumpWidget(
          harness(
            Scaffold(
              body: ChatMessageBubble(message: message, outgoing: outgoing),
            ),
          ),
        );
        final textSurface = tester
            .widgetList<Container>(find.byType(Container))
            .firstWhere((c) => c.decoration is BoxDecoration);
        expect(
          (textSurface.decoration! as BoxDecoration).color,
          outgoing ? const Color(0xFF9B3900) : const Color(0xFF2C2C2C),
        );
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final switchAccount in [false, true]) {
    testWidgets(
      'image batch has one Send control and Sending… label lifecycle; account switch=$switchAccount',
      (tester) async {
        final mediaRepo = MediaRepositoryFake()..failSecond = false;
        final upload = WaitingImageUpload();
        await tester.pumpWidget(
          harness(
            ConversationScreen(
              conversation: conversation,
              currentUserId: 'self',
              repository: mediaRepo,
              mediaUploader: upload,
              pickAttachments: (_) async => [
                XFile.fromData(png, name: 'fixture.png'),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Attachments'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Gallery'));
        await tester.pumpAndSettle();
        expect(find.byType(ChatSendButton), findsOneWidget);
        final target = tester.getCenter(find.byTooltip('Send attachments'));
        await tester.tapAt(target);
        await tester.pump();
        await tester.tapAt(target);
        await tester.pump();
        expect(upload.uploads, 1);
        expect(mediaRepo.sent, isEmpty);
        expect(mediaRepo.sends, 0); // Attachments never invoke text sending.
        expect(find.byType(ChatPendingMediaBubble), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(ChatPendingMediaBubble),
            matching: find.byType(CupertinoActivityIndicator),
          ),
          findsNothing,
        );
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.text('Sending…'), findsOneWidget);
        if (switchAccount) {
          await prefs.saveToken('new-account');
          await tester.pumpAndSettle();
          expect(find.byType(ChatPendingMediaBubble), findsNothing);
        }
        upload.gate.complete();
        await tester.pumpAndSettle();
        expect(mediaRepo.sent, switchAccount ? isEmpty : [101]);
        expect(find.text('Sending…'), findsNothing);
        if (!switchAccount) {
          expect(find.byType(ChatSelectedMediaTray), findsNothing);
          expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
          expect(find.byType(ChatSendButton), findsNothing);
        }
        await tester.pumpWidget(const SizedBox());
        upload.close();
      },
    );
  }
  for (final width in [320.0, 375.0, 393.0, 430.0]) {
    testWidgets(
      'portrait pending image preserves aspect within bounds at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(harness(const Scaffold()));
        await tester.runAsync(
          () => precacheImage(
            MemoryImage(portrait),
            tester.element(find.byType(Scaffold)),
          ),
        );
        await tester.pumpWidget(
          harness(
            Scaffold(
              body: ChatPendingMediaBubble(
                media: ChatMediaSelection(
                  portrait,
                  'portrait.png',
                  'image/png',
                  ChatMessageKind.image,
                ),
                sending: false,
                onRetry: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final image = tester.renderObject<RenderImage>(find.byType(RawImage));
        expect(image.fit, BoxFit.contain);
        expect(image.size.width, lessThanOrEqualTo(width * .75));
        expect(image.size.height, lessThanOrEqualTo(320));
        final fitted = applyBoxFit(
          image.fit!,
          Size(image.image!.width.toDouble(), image.image!.height.toDouble()),
          image.size,
        );
        expect(
          fitted.destination.width / fitted.destination.height,
          closeTo(.5, .001),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'transparent confirmed image still opens the existing fullscreen viewer',
    (tester) async {
      final client = ImageClient(portrait)..gate.complete();
      debugNetworkImageHttpClientProvider = () => client;
      await tester.pumpWidget(
        harness(
          Scaffold(
            body: ChatMessageBubble(
              message: ChatMessage(
                id: 'image',
                senderId: '7',
                kind: ChatMessageKind.image,
                mediaUrl: Uri.parse('https://fixtures.invalid/image.png'),
              ),
              outgoing: true,
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => precacheImage(
          const NetworkImage('https://fixtures.invalid/image.png'),
          tester.element(find.byType(ChatMessageBubble)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();
      expect(find.byType(ChatImageViewer), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ChatMessageBubble), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      debugNetworkImageHttpClientProvider = null;
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    },
  );
}
