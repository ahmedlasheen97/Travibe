import 'package:travibe/features/chats/widgets/chat_composer.dart';
import 'package:travibe/features/chats/cubit/chat_cubit.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/chats/cubit/chat_audio_controller.dart';
import 'package:travibe/features/chats/data/chat_device_media.dart';
import 'package:travibe/features/chats/data/chat_image_saver.dart';
import 'package:travibe/features/chats/data/chat_media_selection.dart';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/data/chat_presence_presentation.dart';
import 'package:travibe/features/chats/screens/chat_image_viewer.dart';
import 'package:travibe/features/chats/screens/conversation_screen.dart';
import 'package:travibe/features/chats/widgets/chat_selected_media_tray.dart';
import 'package:travibe/features/chats/widgets/chat_widgets.dart';
import 'chat_fakes.dart';

final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aKp8AAAAASUVORK5CYII=',
);

class PermissionsFake extends ChatDeviceMedia {
  ChatMicrophonePermission status = ChatMicrophonePermission.granted;
  ChatMicrophonePermission requested = ChatMicrophonePermission.granted;
  int prompts = 0, settings = 0, saves = 0;
  bool failSave = false;
  @override
  Future<ChatMicrophonePermission> microphone({bool request = false}) async {
    if (request) {
      prompts++;
      return requested;
    }
    return status;
  }

  @override
  Future<void> openSettings() async {
    settings++;
  }

  @override
  Future<void> saveImage(Uint8List bytes) async {
    if (failSave) throw PlatformException(code: 'save_failed');
    saves++;
  }
}

class RecorderFake implements AudioRecorder {
  String? path;
  int starts = 0, pauses = 0, resumes = 0, cancels = 0, disposals = 0;
  final levels = StreamController<Amplitude>.broadcast(sync: true);
  final states = StreamController<RecordState>.broadcast(sync: true);
  @override
  Future<bool> hasPermission({bool request = true}) async => true;
  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    this.path = path;
    starts++;
    await File(path).writeAsBytes([1, 2, 3]);
  }

  @override
  Stream<Amplitude> onAmplitudeChanged(Duration interval) => levels.stream;
  @override
  Stream<RecordState> onStateChanged() => states.stream;
  @override
  Future<void> pause() async {
    pauses++;
  }

  @override
  Future<void> resume() async {
    resumes++;
  }

  @override
  Future<String?> stop() async => path;
  @override
  Future<void> cancel() async {
    cancels++;
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class PreviewPlayerFake implements AudioPlayer {
  final states = StreamController<PlayerState>.broadcast(sync: true);
  String? url;
  int plays = 0, pauses = 0;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  Stream<PlayerException> get errorStream => const Stream.empty();
  @override
  ProcessingState get processingState => ProcessingState.ready;
  @override
  Future<Duration?> setUrl(
    String url, {
    Map<String, String>? headers,
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async {
    this.url = url;
    return const Duration(seconds: 1);
  }

  @override
  Future<void> play() async {
    plays++;
    states.add(PlayerState(true, ProcessingState.ready));
  }

  @override
  Future<void> pause() async {
    pauses++;
    states.add(PlayerState(false, ProcessingState.ready));
  }

  @override
  Future<void> stop() async {
    states.add(PlayerState(false, ProcessingState.idle));
  }

  @override
  Future<void> dispose() async {
    await states.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class DownloadAdapter implements HttpClientAdapter {
  Uint8List bytes = png;
  int status = 200;
  RequestOptions? request;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    request = options;
    return ResponseBody.fromBytes(bytes, status);
  }

  @override
  void close({bool force = false}) {}
}

class ViewerSaverFake extends ChatImageSaver {
  bool fail = false;
  int calls = 0;
  @override
  Future<void> save(
    Uri url, {
    required CancelToken cancel,
    required bool Function() isActive,
  }) async {
    calls++;
    if (fail) throw PlatformException(code: 'save_failed');
  }
}

Widget screen(Widget child) => ScreenUtilInit(
  designSize: const Size(390, 844),
  builder: (_, _) => MaterialApp(theme: ThemeData.dark(), home: child),
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final prefs = PreferencesManager();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await prefs.init();
    await prefs.saveToken('fixture');
  });
  for (final permission in ChatMicrophonePermission.values) {
    test(
      'microphone $permission is checked only on tap and never bypassed',
      () async {
        final native = PermissionsFake()..status = permission;
        if (permission == ChatMicrophonePermission.denied) {
          native.requested = permission;
        }
        final recorder = RecorderFake();
        final audio = ChatAudioController(
          recorder: recorder,
          deviceMedia: native,
          recordingSupported: true,
        );
        expect(recorder.starts, 0);
        expect(native.prompts, 0);
        await audio.startRecording();
        final granted =
            permission == ChatMicrophonePermission.granted ||
            permission == ChatMicrophonePermission.notDetermined;
        expect(recorder.starts, granted ? 1 : 0);
        if (permission == ChatMicrophonePermission.permanentlyDenied ||
            permission == ChatMicrophonePermission.restricted) {
          expect(audio.needsSettings, isTrue);
          await audio.openSettings();
          expect(native.settings, 1);
        }
        expect(
          native.prompts,
          (permission == ChatMicrophonePermission.notDetermined ||
                  permission == ChatMicrophonePermission.denied)
              ? 1
              : 0,
        );
        await audio.cancelRecording();
        audio.dispose();
        await Future<void>.delayed(Duration.zero);
      },
    );
  }
  test(
    'records levels, pauses/resumes, keeps a preview draft and releases recording resources',
    () async {
      final recorder = RecorderFake();
      final audio = ChatAudioController(
        recorder: recorder,
        deviceMedia: PermissionsFake(),
        recordingSupported: true,
      );
      await audio.startRecording();
      recorder.levels.add(Amplitude(current: -20, max: 0));
      expect(audio.levels.single, closeTo(2 / 3, .01));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await audio.pauseRecording();
      expect(audio.recordingPaused, isTrue);
      await audio.pauseRecording();
      expect(audio.recordingPaused, isFalse);
      expect(recorder.pauses, 1);
      expect(recorder.resumes, 1);
      await audio.stopRecording();
      expect(audio.draft?.bytes, [1, 2, 3]);
      expect(audio.recording, isFalse);
      expect(await File(recorder.path!).exists(), isFalse);
      audio.discardDraft();
      expect(audio.draft, isNull);
      audio.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(recorder.disposals, 1);
    },
  );
  test(
    'voice draft previews actual captured bytes and toggles pause without sending',
    () async {
      final player = PreviewPlayerFake();
      final audio = ChatAudioController(
        player: player,
        deviceMedia: PermissionsFake(),
        recordingSupported: true,
      );
      audio.draft = ChatVoiceDraft(Uint8List.fromList([1, 2, 3]), 1000);
      await audio.previewDraft();
      expect(Uri.parse(player.url!).scheme, 'file');
      expect(await File.fromUri(Uri.parse(player.url!)).readAsBytes(), [
        1,
        2,
        3,
      ]);
      expect(player.plays, 1);
      expect(audio.playing, isTrue);
      await audio.previewDraft();
      expect(player.pauses, 1);
      expect(audio.playing, isFalse);
      audio.discardDraft();
      await Future<void>.delayed(Duration.zero);
      audio.dispose();
      await Future<void>.delayed(Duration.zero);
    },
  );
  test(
    'app interruption stops capture, retains finished draft and forbids a background restart',
    () async {
      final recorder = RecorderFake();
      final audio = ChatAudioController(
        recorder: recorder,
        deviceMedia: PermissionsFake(),
        recordingSupported: true,
      );
      await audio.startRecording();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await audio.pause();
      expect(audio.recording, isFalse);
      expect(audio.draft, isNotNull);
      audio.discardDraft();
      await audio.startRecording();
      expect(recorder.starts, 1);
      audio.dispose();
      await Future<void>.delayed(Duration.zero);
    },
  );
  test(
    'account switch cancels microphone and drops captured draft and levels',
    () async {
      final recorder = RecorderFake();
      final audio = ChatAudioController(
        recorder: recorder,
        deviceMedia: PermissionsFake(),
        recordingSupported: true,
      );
      await audio.startRecording();
      await prefs.saveToken('other');
      await Future<void>.delayed(Duration.zero);
      expect(audio.recording, isFalse);
      expect(audio.draft, isNull);
      expect(recorder.cancels, greaterThan(0));
      expect(recorder.disposals, 1);
      await audio.startRecording();
      expect(recorder.starts, 1);
      audio.dispose();
    },
  );
  test(
    'native microphone bridge exposes all permission states without startup request',
    () async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ChatDeviceMedia.channel, (call) async {
            calls.add(call.method);
            return call.method == 'microphoneStatus'
                ? 'notDetermined'
                : 'granted';
          });
      const device = ChatDeviceMedia();
      expect(await device.microphone(), ChatMicrophonePermission.notDetermined);
      expect(calls, ['microphoneStatus']);
      expect(
        await device.microphone(request: true),
        ChatMicrophonePermission.granted,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ChatDeviceMedia.channel, null);
    },
  );
  test(
    'presence priority respects hidden fields, blocking, pending requests and unknown online strings',
    () {
      ChatConversation thread(
        ChatParticipant peer, {
        bool accepted = true,
        bool blocked = false,
      }) => ChatConversation(
        id: '42',
        participant: peer,
        isAccepted: accepted,
        isBlocked: blocked,
      );
      final peer = ChatParticipant(
        id: '7',
        name: 'Fixture',
        onlineStatus: 'unspecified',
        lastSeenAt: DateTime.now().subtract(const Duration(hours: 2)),
      );
      expect(
        chatPresenceLabel(thread(peer), typing: true, memberOnline: true),
        'Typing…',
      );
      expect(
        chatPresenceLabel(thread(peer), typing: false, memberOnline: true),
        'Online',
      );
      expect(
        chatPresenceLabel(thread(peer), typing: false, memberOnline: false),
        startsWith('Last seen 2h'),
      );
      expect(
        chatPresenceLabel(
          thread(const ChatParticipant(id: '7', name: 'Fixture')),
          typing: false,
          memberOnline: true,
        ),
        isNull,
      );
      expect(
        chatPresenceLabel(
          thread(peer, accepted: false),
          typing: true,
          memberOnline: true,
        ),
        isNull,
      );
      expect(
        chatPresenceLabel(
          thread(peer, blocked: true),
          typing: true,
          memberOnline: true,
        ),
        isNull,
      );
    },
  );
  test(
    'selection queue retains failed/unconfirmed items in order and rejects excessive batches',
    () {
      final a = ChatMediaSelection(
            png,
            'a.png',
            'image/png',
            ChatMessageKind.image,
          ),
          b = ChatMediaSelection(
            png,
            'b.png',
            'image/png',
            ChatMessageKind.image,
          );
      final queue = ChatMediaSelectionQueue()..addAll([a, b]);
      expect(queue.items, [a, b]);
      queue.remove(a);
      expect(queue.first, b);
      queue.clear();
      expect(queue.isEmpty, isTrue);
      expect(() => queue.addAll(List.filled(11, a)), throwsFormatException);
      expect(queue.isEmpty, isTrue);
    },
  );
  test(
    'gallery saver validates image bytes and never sends bearer credentials to storage',
    () async {
      final adapter = DownloadAdapter(), native = PermissionsFake();
      final dio = Dio()..httpClientAdapter = adapter;
      final saver = ChatImageSaver(dio: dio, device: native);
      await saver.save(
        Uri.parse('https://media.invalid/image'),
        cancel: CancelToken(),
        isActive: () => true,
      );
      expect(native.saves, 1);
      expect(adapter.request!.headers.containsKey('Authorization'), isFalse);
      adapter.bytes = Uint8List.fromList([1, 2, 3]);
      await expectLater(
        saver.save(
          Uri.parse('https://media.invalid/image'),
          cancel: CancelToken(),
          isActive: () => true,
        ),
        throwsA(anything),
      );
      expect(native.saves, 1);
      saver.dispose();
    },
  );
  test(
    'gallery failure and account changes never become a successful save',
    () async {
      final native = PermissionsFake()..failSave = true;
      final dio = Dio()..httpClientAdapter = DownloadAdapter();
      final saver = ChatImageSaver(dio: dio, device: native);
      await expectLater(
        saver.save(
          Uri.parse('https://media.invalid/image'),
          cancel: CancelToken(),
          isActive: () => true,
        ),
        throwsA(isA<PlatformException>()),
      );
      native.failSave = false;
      await expectLater(
        saver.save(
          Uri.parse('https://media.invalid/image'),
          cancel: CancelToken(),
          isActive: () => false,
        ),
        throwsFormatException,
      );
      expect(native.saves, 0);
      saver.dispose();
    },
  );
  testWidgets(
    'only one message detail opens; incoming messages never claim Seen',
    (tester) async {
      final repo = FakeChatRepository()
        ..messageItems = [
          ChatMessage(
            id: '2',
            senderId: 'self',
            kind: ChatMessageKind.text,
            text: 'Outgoing',
            readAt: DateTime.utc(2026),
            createdAt: DateTime.utc(2026),
          ),
          ChatMessage(
            id: '1',
            senderId: 'other',
            kind: ChatMessageKind.text,
            text: 'Incoming',
            readAt: DateTime.utc(2026),
            createdAt: DateTime.utc(2026),
          ),
        ];
      await tester.pumpWidget(
        screen(
          ConversationScreen(
            conversation: conversation,
            repository: repo,
            currentUserId: 'self',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Seen'), findsNothing);
      await tester.tap(find.text('Outgoing'));
      await tester.pump();
      expect(find.textContaining('Seen'), findsOneWidget);
      await tester.tap(find.text('Incoming'));
      await tester.pump();
      expect(find.textContaining('Seen'), findsNothing);
      expect(
        tester
            .widgetList<ChatMessageBubble>(find.byType(ChatMessageBubble))
            .where((m) => m.detailsExpanded),
        hasLength(1),
      );
      await tester.tap(find.text('Incoming'));
      await tester.pump();
      expect(
        tester
            .widgetList<ChatMessageBubble>(find.byType(ChatMessageBubble))
            .where((m) => m.detailsExpanded),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final width in [320.0, 375.0, 393.0, 430.0]) {
    testWidgets(
      'selected images fit width $width; remove and send actions stay accessible',
      (tester) async {
        tester.view.physicalSize = Size(width, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final queue = ChatMediaSelectionQueue()
          ..addAll(
            List.generate(
              3,
              (i) => ChatMediaSelection(
                png,
                '$i.png',
                'image/png',
                ChatMessageKind.image,
              ),
            ),
          );
        var sent = 0;
        await tester.pumpWidget(
          screen(
            Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ChatSelectedMediaTray(
                      items: queue.items,
                      onRemove: (item) => setState(() => queue.remove(item)),
                      onSend: () => sent++,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byTooltip('Remove selected attachment 1'));
        await tester.pump();
        expect(queue.items, hasLength(2));
        await tester.tap(find.byTooltip('Send attachments'));
        expect(sent, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'selected tray and composer remain above a small landscape keyboard with scaled text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 430);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final audio = ChatAudioController();
      final text = TextEditingController();
      final composer = ChatComposerCubit(
        repository: FakeChatRepository(),
        conversation: conversation,
        onSent: (_) {},
      );
      final media = ChatMediaSelection(
        png,
        'fixture.png',
        'image/png',
        ChatMessageKind.image,
      );
      await tester.pumpWidget(
        screen(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.6)),
              child: Scaffold(
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
                      selectedMediaTray: ChatSelectedMediaTray(
                        items: [media],
                        onRemove: (_) {},
                        onSend: () {},
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        tester.getBottomRight(find.byType(TextField)).dy,
        lessThanOrEqualTo(250),
      );
      await tester.pumpWidget(const SizedBox());
      audio.dispose();
      text.dispose();
      await composer.close();
    },
  );
  for (final fail in [false, true]) {
    testWidgets(
      'fullscreen viewer confirms gallery save only on success; failure=$fail',
      (tester) async {
        final saver = ViewerSaverFake()..fail = fail;
        await tester.pumpWidget(
          screen(
            ChatImageViewer(
              url: Uri.parse('https://media.invalid/image'),
              saver: saver,
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(InteractiveViewer), findsOneWidget);
        await tester.tap(find.byTooltip('Save image to gallery'));
        await tester.pump();
        expect(saver.calls, 1);
        expect(
          find.text('Image Saved to Gallery'),
          fail ? findsNothing : findsOneWidget,
        );
        if (fail) {
          expect(find.textContaining('Unable to save image.'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
        saver.dispose();
      },
    );
  }
}
