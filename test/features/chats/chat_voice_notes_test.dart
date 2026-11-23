import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/chats/cubit/chat_audio_controller.dart';
import 'package:travibe/features/chats/cubit/chat_cubit.dart';
import 'package:travibe/features/chats/data/chat_device_media.dart';
import 'package:travibe/features/chats/data/chat_media_selection.dart';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/data/chat_voice_waveform.dart';
import 'package:travibe/features/chats/widgets/chat_composer.dart';
import 'package:travibe/features/chats/widgets/chat_pending_media_bubble.dart';
import 'package:travibe/features/chats/widgets/chat_voice_composer.dart';
import 'package:travibe/features/chats/widgets/chat_widgets.dart';
import 'chat_fakes.dart';
import 'chat_interactions_test.dart'
    show FakeStopwatch, PermissionsFake, PreviewPlayerFake, RecorderFake, png;
import 'chat_widgets_test.dart' show harness;

/// The system prompt backgrounds the app while it is showing.
class PromptingPermissions extends PermissionsFake {
  PromptingPermissions(this.onPrompt);
  final void Function() onPrompt;
  @override
  Future<ChatMicrophonePermission> microphone({bool request = false}) async {
    if (request) onPrompt();
    return super.microphone(request: request);
  }
}

ChatAudioController _controller({
  RecorderFake? recorder,
  ChatDeviceMedia? device,
  FakeStopwatch? clock,
  PreviewPlayerFake? player,
  Duration maxRecording = const Duration(minutes: 5),
  Duration resumeTimeout = const Duration(seconds: 3),
}) => ChatAudioController(
  recorder: recorder ?? RecorderFake(),
  deviceMedia: device ?? PermissionsFake(),
  recordingSupported: true,
  clock: clock ?? FakeStopwatch(),
  player: player,
  maxRecording: maxRecording,
  resumeTimeout: resumeTimeout,
);

/// Lets real file I/O started inside the fake-async zone finish step by step.
Future<void> _settleIo(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

void main() {
  final prefs = PreferencesManager();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await prefs.init();
    await prefs.saveToken('fixture');
  });

  group('ChatAudioController', () {
    test(
      'first recording starts right after granting the mic prompt',
      () async {
        late ChatAudioController audio;
        final recorder = RecorderFake();
        final device = PromptingPermissions(() {
          unawaited(audio.pause());
          Timer(const Duration(milliseconds: 20), audio.resume);
        })..status = ChatMicrophonePermission.notDetermined;
        audio = _controller(recorder: recorder, device: device);
        await audio.startRecording();
        expect(device.prompts, 1);
        expect(recorder.starts, 1);
        expect(audio.recording, isTrue);
        await audio.cancelRecording();
        audio.dispose();
      },
    );

    test('a prompt that never returns to the app does not record', () async {
      late ChatAudioController audio;
      final recorder = RecorderFake();
      final device = PromptingPermissions(() => unawaited(audio.pause()))
        ..status = ChatMicrophonePermission.notDetermined;
      audio = _controller(
        recorder: recorder,
        device: device,
        resumeTimeout: const Duration(milliseconds: 20),
      );
      await audio.startRecording();
      expect(recorder.starts, 0);
      expect(audio.recording, isFalse);
      audio.dispose();
    });

    test('auto-stops at the maximum length into a preview', () async {
      final clock = FakeStopwatch();
      final audio = _controller(
        clock: clock,
        maxRecording: const Duration(minutes: 5),
      );
      await audio.startRecording();
      clock.value = const Duration(minutes: 5);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(audio.recording, isFalse);
      expect(audio.draft?.durationMs, 300000);
      audio.dispose();
    });

    test('under one second leaves no draft and a one-shot hint', () async {
      final clock = FakeStopwatch();
      final audio = _controller(clock: clock);
      await audio.startRecording();
      clock.value = const Duration(milliseconds: 600);
      await audio.stopRecording();
      expect(audio.draft, isNull);
      expect(audio.takeNotice(), contains('too short'));
      expect(audio.takeNotice(), isNull);
      audio.dispose();
    });

    test(
      'recorder stopping by itself keeps the recording as a preview',
      () async {
        final clock = FakeStopwatch();
        final recorder = RecorderFake();
        final audio = _controller(clock: clock, recorder: recorder);
        await audio.startRecording();
        clock.value = const Duration(seconds: 4);
        recorder.states.add(RecordState.stop);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(audio.recording, isFalse);
        expect(audio.draft?.durationMs, 4000);
        expect(recorder.cancels, 0);
        audio.dispose();
      },
    );

    test('draft carries the captured waveform, normalised', () async {
      final clock = FakeStopwatch();
      final recorder = RecorderFake();
      final audio = _controller(clock: clock, recorder: recorder);
      await audio.startRecording();
      for (final db in [-50.0, -30.0, -10.0, -40.0]) {
        recorder.levels.add(Amplitude(current: db, max: 0));
      }
      clock.value = const Duration(seconds: 2);
      await audio.stopRecording();
      final bars = audio.draft!.waveform;
      expect(bars, hasLength(chatVoiceWaveformBars));
      expect(bars.reduce((a, b) => a > b ? a : b), 1.0);
      audio.dispose();
    });

    test('seek moves only the loaded message', () async {
      final player = PreviewPlayerFake();
      final audio = _controller(player: player);
      audio.draft = ChatVoiceDraft(Uint8List.fromList([1, 2, 3]), 1000);
      await audio.seek(ChatAudioController.draftId, .5);
      expect(player.seeked, isNull);
      await audio.previewDraft();
      await audio.seek(ChatAudioController.draftId, .5);
      expect(player.seeked, const Duration(milliseconds: 500));
      await audio.seek('other', .2);
      expect(player.seeked, const Duration(milliseconds: 500));
      audio.discardDraft();
      await Future<void>.delayed(Duration.zero);
      audio.dispose();
    });
  });

  test('placeholder waveform is stable per duration', () {
    expect(chatPlaceholderWaveform(12000), chatPlaceholderWaveform(12000));
    expect(
      chatPlaceholderWaveform(12000),
      isNot(chatPlaceholderWaveform(36000)),
    );
    expect(chatPlaceholderWaveform(null), hasLength(chatVoiceWaveformBars));
  });

  group('voice composer', () {
    late ChatComposerCubit composer;
    late TextEditingController text;
    late int sent;
    setUp(() {
      composer = ChatComposerCubit(
        repository: FakeChatRepository(),
        conversation: conversation,
        onSent: (_) {},
      );
      text = TextEditingController();
      sent = 0;
    });
    tearDown(() async {
      await composer.close();
      text.dispose();
    });
    Widget build(ChatAudioController audio) => harness(
      Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ChatComposer(
            composer: composer,
            text: text,
            audio: audio,
            canSend: true,
            uploading: false,
            onAttachment: () {},
            onTyped: () {},
            onSendVoice: () => sent++,
          ),
        ),
      ),
    );
    Color pillColor(WidgetTester tester) =>
        ((tester.widget<Container>(
                  find
                      .descendant(
                        of: find.byKey(const ValueKey('chat-voice-composer')),
                        matching: find.byType(Container),
                      )
                      .first,
                )).decoration
                as BoxDecoration)
            .color!;

    testWidgets('recording: orange pill with stop, trash and send; no pause', (
      tester,
    ) async {
      final clock = FakeStopwatch();
      final audio = _controller(clock: clock);
      await tester.runAsync(audio.startRecording);
      await tester.pumpWidget(build(audio));
      expect(find.byType(TextField), findsNothing);
      expect(find.byTooltip('Stop recording'), findsOneWidget);
      expect(find.byTooltip('Discard voice note'), findsOneWidget);
      expect(find.byTooltip('Send voice note'), findsOneWidget);
      expect(find.byTooltip('Pause recording'), findsNothing);
      expect(pillColor(tester), DarkColors.primaryColor);

      // Stop → grey preview pill with ▶.
      clock.value = const Duration(seconds: 2);
      await tester.tap(find.byTooltip('Stop recording'));
      await _settleIo(tester);
      expect(audio.draft, isNotNull);
      expect(find.byTooltip('Play voice note'), findsOneWidget);
      expect(pillColor(tester), chatVoicePreviewColor);
      expect(find.text('0:02'), findsOneWidget);
      expect(sent, 0);
      await tester.pumpWidget(const SizedBox());
      audio.dispose();
    });

    testWidgets('send while recording stops and sends immediately', (
      tester,
    ) async {
      final clock = FakeStopwatch();
      final audio = _controller(clock: clock);
      await tester.runAsync(audio.startRecording);
      await tester.pumpWidget(build(audio));
      clock.value = const Duration(seconds: 3);
      await tester.tap(find.byTooltip('Send voice note'));
      await _settleIo(tester);
      expect(audio.recording, isFalse);
      expect(sent, 1);
      await tester.pumpWidget(const SizedBox());
      audio.dispose();
    });

    testWidgets('too-short recording shows a hint and returns to text', (
      tester,
    ) async {
      final clock = FakeStopwatch();
      final audio = _controller(clock: clock);
      await tester.runAsync(audio.startRecording);
      await tester.pumpWidget(build(audio));
      clock.value = const Duration(milliseconds: 400);
      await tester.tap(find.byTooltip('Stop recording'));
      await _settleIo(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('too short'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(audio.draft, isNull);
      await tester.pumpWidget(const SizedBox());
      audio.dispose();
    });

    testWidgets('trash discards short drafts without asking', (tester) async {
      final audio = _controller()
        ..draft = ChatVoiceDraft(Uint8List.fromList([1]), 2000);
      await tester.pumpWidget(build(audio));
      await tester.tap(find.byTooltip('Discard voice note'));
      await tester.pumpAndSettle();
      expect(find.text('Discard voice note?'), findsNothing);
      expect(audio.draft, isNull);
      expect(find.byType(TextField), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      audio.dispose();
    });

    testWidgets('trash asks before discarding 3s or longer', (tester) async {
      final audio = _controller()
        ..draft = ChatVoiceDraft(Uint8List.fromList([1]), 5000);
      await tester.pumpWidget(build(audio));
      await tester.tap(find.byTooltip('Discard voice note'));
      await tester.pumpAndSettle();
      expect(find.text('Discard voice note?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(audio.draft, isNotNull);
      await tester.tap(find.byTooltip('Discard voice note'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(audio.draft, isNull);
      await tester.pumpWidget(const SizedBox());
      audio.dispose();
    });

    testWidgets('permanently denied mic shows exactly one Open Settings', (
      tester,
    ) async {
      final device = PermissionsFake()
        ..status = ChatMicrophonePermission.permanentlyDenied;
      final audio = _controller(device: device);
      await tester.pumpWidget(build(audio));
      await tester.tap(find.byTooltip('Record voice message'));
      await tester.pumpAndSettle();
      expect(find.text('Open Settings'), findsOneWidget);
      expect(device.prompts, 0);
      await tester.tap(find.text('Not Now'));
      await tester.pumpAndSettle();
      expect(find.text('Open Settings'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      audio.dispose();
    });
  });

  group('voice bubbles', () {
    testWidgets('counts down while playing and seeks by dragging', (
      tester,
    ) async {
      final seeks = <double>[];
      await tester.pumpWidget(
        harness(
          Scaffold(
            body: Center(
              child: ChatVoiceMessage(
                duration: const Duration(seconds: 16),
                position: const Duration(seconds: 4),
                progress: .25,
                playing: true,
                onToggle: () {},
                onSeek: seeks.add,
              ),
            ),
          ),
        ),
      );
      expect(find.text('0:12'), findsOneWidget);
      expect(find.byTooltip('Pause voice message'), findsOneWidget);
      final wave = find.byKey(const ValueKey('chat-voice-seek'));
      await tester.drag(wave, const Offset(30, 0));
      expect(seeks, isNotEmpty);
      expect(seeks.every((f) => f >= 0 && f <= 1), isTrue);
    });

    testWidgets('incoming grey and outgoing dark orange voice bubbles', (
      tester,
    ) async {
      Color colorOf(bool outgoing) {
        final box = tester.widget<Container>(
          find
              .ancestor(
                of: find.byType(ChatVoiceMessage),
                matching: find.byType(Container),
              )
              .first,
        );
        return (box.decoration as BoxDecoration).color!;
      }

      for (final outgoing in [false, true]) {
        await tester.pumpWidget(
          harness(
            Scaffold(
              body: ChatMessageBubble(
                outgoing: outgoing,
                message: const ChatMessage(
                  id: 'v1',
                  senderId: 'other',
                  kind: ChatMessageKind.audio,
                  duration: Duration(seconds: 36),
                ),
              ),
            ),
          ),
        );
        expect(find.text('0:36'), findsOneWidget);
        expect(
          colorOf(outgoing),
          outgoing ? const Color(0xFF9B3900) : const Color(0xFF2C2C2C),
        );
      }
    });

    testWidgets('pending voice note: label + ring, one retry on failure', (
      tester,
    ) async {
      var retries = 0, discards = 0;
      final media = ChatMediaSelection(
        png,
        'recording.m4a',
        'audio/mp4',
        ChatMessageKind.audio,
        durationMs: 12000,
      );
      Widget bubble(bool sending) => harness(
        Scaffold(
          body: ChatPendingMediaBubble(
            media: media,
            sending: sending,
            progress: .3,
            onRetry: () => retries++,
            onDiscard: () => discards++,
          ),
        ),
      );
      await tester.pumpWidget(bubble(true));
      expect(find.text('Voice note · 0:12'), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-upload-ring')), findsOneWidget);
      expect(find.textContaining('recording.m4a'), findsNothing);

      await tester.pumpWidget(bubble(false));
      expect(find.text('Voice note · 0:12'), findsOneWidget);
      expect(find.textContaining('retry', findRichText: true), findsOneWidget);
      await tester.tap(find.text('Failed to send. Tap to retry.'));
      expect(retries, 1);
      await tester.tap(find.byTooltip('Discard voice note'));
      expect(discards, 1);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
