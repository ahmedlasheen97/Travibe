import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/chats/cubit/chat_audio_controller.dart';
import 'package:travibe/features/chats/cubit/chat_cubit.dart';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/data/chat_reachability.dart';
import 'package:travibe/features/chats/data/chat_repository.dart';
import 'package:travibe/features/chats/screens/conversation_screen.dart';
import 'package:travibe/features/chats/widgets/chat_composer.dart';
import 'package:travibe/features/chats/widgets/chat_emoji_picker.dart';
import 'package:travibe/features/chats/widgets/chat_network_banner.dart';
import 'package:travibe/features/chats/widgets/chat_widgets.dart';
import 'chat_fakes.dart';
import 'chat_widgets_test.dart' show harness;

class RetryRepo extends FakeChatRepository {
  Object? rejection;
  int histories = 0;
  @override
  Future<ChatPage<ChatMessage>> messages(
    String id, {
    String? continuation,
  }) async {
    histories++;
    return ChatPage(messageItems);
  }

  @override
  Future<ChatMessage> sendText(String id, String text) async {
    sends++;
    if (rejection != null) throw rejection!;
    return sending?.future ??
        ChatMessage(
          id: '123',
          senderId: 'self',
          conversationId: id,
          kind: ChatMessageKind.text,
          text: text,
        );
  }
}

class SendAdapter implements HttpClientAdapter {
  DioExceptionType? failure;
  Object? cause;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    if (failure != null) {
      throw DioException(requestOptions: options, type: failure!, error: cause);
    }
    return ResponseBody.fromString(
      jsonEncode({
        'data': {'id': 123, 'conversation_id': 42},
      }),
      201,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final prefs = PreferencesManager();
  bool? connected;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await prefs.init();
    await prefs.saveToken('fixture');
    ChatReachability.instance.reset();
    connected = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('travibe/chat_media'),
          (call) async => call.method == 'networkStatus' ? connected : null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('emoji_picker_flutter'), (
          call,
        ) async {
          if (call.method == 'getSupportedEmojis') {
            return List.filled((call.arguments['source'] as List).length, true);
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('travibe/chat_media'),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('emoji_picker_flutter'),
          null,
        );
  });

  test(
    'emoji insertion respects cursor, selection, newlines, ZWJ and grapheme boundaries',
    () {
      var value = insertChatEmoji(
        const TextEditingValue(
          text: 'Hello world',
          selection: TextSelection.collapsed(offset: 5),
        ),
        '😀',
      );
      expect(value.text, 'Hello😀 world');
      expect(value.selection.baseOffset, 7);
      value = insertChatEmoji(
        const TextEditingValue(
          text: 'Hello world',
          selection: TextSelection(baseOffset: 6, extentOffset: 11),
        ),
        '👩🏽‍💻',
      );
      expect(value.text, 'Hello 👩🏽‍💻');
      expect(value.selection.baseOffset, value.text.length);
      value = insertChatEmoji(
        const TextEditingValue(
          text: 'مرحبا\nworld',
          selection: TextSelection.collapsed(offset: 6),
        ),
        '👨‍👩‍👧‍👦',
      );
      expect(value.text, 'مرحبا\n👨‍👩‍👧‍👦world');
      value = insertChatEmoji(value, '❤️');
      expect(value.text, 'مرحبا\n👨‍👩‍👧‍👦❤️world');
      value = insertChatEmoji(
        const TextEditingValue(
          text: 'A👩‍💻B',
          selection: TextSelection.collapsed(offset: 2),
        ),
        '😀',
      );
      expect(value.text, 'A👩‍💻😀B');
      expect(value.composing, TextRange.empty);
    },
  );

  test(
    'pre-send transport rejection is definite; receive timeout remains ambiguous',
    () async {
      final adapter = SendAdapter()
        ..failure = DioExceptionType.connectionTimeout;
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = LaravelChatRepository(dio: dio);
      await expectLater(
        repository.sendText('42', 'fixture'),
        throwsA(isA<ChatPreSendFailure>()),
      );
      adapter.failure = DioExceptionType.receiveTimeout;
      await expectLater(
        repository.sendText('42', 'fixture'),
        throwsA(
          isA<ApiError>().having(
            (e) => e is ChatPreSendFailure,
            'not pre-send',
            false,
          ),
        ),
      );
      dio.close();
    },
  );

  test(
    'connect-time socket failure is pre-send; closed-after-send stays ambiguous',
    () async {
      final adapter = SendAdapter()
        ..failure = DioExceptionType.connectionError
        ..cause = const SocketException('Network is unreachable');
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = LaravelChatRepository(dio: dio);
      await expectLater(
        repository.sendText('42', 'fixture'),
        throwsA(isA<ChatPreSendFailure>()),
      );
      adapter.cause = const HttpException(
        'Connection closed before full header was received',
      );
      await expectLater(
        repository.sendText('42', 'fixture'),
        throwsA(
          isA<ApiError>().having(
            (e) => e is ChatPreSendFailure,
            'not pre-send',
            false,
          ),
        ),
      );
      dio.close();
    },
  );

  test(
    'any HTTP response marks chat reachability; transport failure does not',
    () async {
      final reachability = ChatReachability();
      final adapter = SendAdapter()
        ..failure = DioExceptionType.connectionError
        ..cause = const SocketException('offline');
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = LaravelChatRepository(
        dio: dio,
        reachability: reachability,
      );
      await expectLater(
        repository.sendText('42', 'fixture'),
        throwsA(anything),
      );
      expect(reachability.lastSuccess, isNull);
      adapter.failure = null;
      await expectLater(
        repository.sendText('42', 'fixture'),
        throwsA(anything),
      );
      expect(reachability.lastSuccess, isNotNull);
      dio.close();
    },
  );

  test(
    'confirmed 201 with incomplete resource retains only a verified server correlation ID',
    () async {
      final dio = Dio()..httpClientAdapter = SendAdapter();
      final repository = LaravelChatRepository(dio: dio);
      await expectLater(
        repository.sendText('42', 'fixture'),
        throwsA(
          isA<ChatUnconfirmedSend>().having(
            (e) => e.serverMessageId,
            'id',
            '123',
          ),
        ),
      );
      dio.close();
    },
  );

  test(
    'known acknowledgement reconciles without resend; identical text alone cannot',
    () async {
      final repo = RetryRepo()
        ..rejection = ChatUnconfirmedSend(serverMessageId: '123');
      final composer = ChatComposerCubit(
        repository: repo,
        conversation: conversation,
        onSent: (_) {},
      );
      composer.edit('fixture');
      await composer.send();
      final localId = composer.state.localMessages.single.id;
      expect(
        composer.reconcileUnknown(localId, [
          ChatMessage(
            id: '124',
            senderId: 'self',
            conversationId: conversation.id,
            kind: ChatMessageKind.text,
            text: 'fixture',
          ),
        ]),
        false,
      );
      expect(
        composer.reconcileUnknown(localId, [
          ChatMessage(
            id: '123',
            senderId: 'self',
            conversationId: conversation.id,
            kind: ChatMessageKind.text,
            text: 'fixture',
          ),
        ]),
        true,
      );
      expect(composer.state.localMessages, isEmpty);
      expect(repo.sends, 1);
      expect(composer.state.draft, isEmpty);
      // A known accepted record that is now deleted must not be resent either.
      composer.edit('removed fixture');
      await composer.send();
      final deletedLocal = composer.state.localMessages.single.id;
      expect(
        composer.reconcileUnknown(deletedLocal, [
          ChatMessage(
            id: '123',
            senderId: 'self',
            conversationId: conversation.id,
            kind: ChatMessageKind.text,
            isDeleted: true,
          ),
        ]),
        true,
      );
      expect(composer.state.localMessages, isEmpty);
      expect(repo.sends, 2);
      await composer.close();
    },
  );

  testWidgets(
    'definite failed bubble retries directly, shows in-bubble spinner, locks taps and keeps ID on failure',
    (tester) async {
      final repo = RetryRepo()
        ..messageItems = []
        ..rejection = ApiError(message: 'Rejected fixture', statusCode: 422);
      await tester.pumpWidget(
        harness(
          ConversationScreen(
            conversation: conversation,
            repository: repo,
            currentUserId: 'self',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'fixture');
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      expect(find.text('Failed to send. Tap to retry.'), findsOneWidget);
      expect(find.text('Rejected fixture'), findsNothing);
      final composer = tester
          .widget<ChatComposer>(find.byType(ChatComposer))
          .composer;
      final localId = composer.state.localMessages.single.id;
      repo.rejection = null;
      repo.sending = Completer();
      await tester.tap(
        find
            .descendant(
              of: find.byType(ChatMessageBubble),
              matching: find.text('fixture'),
            )
            .first,
      );
      await tester.pump();
      expect(find.byType(Dialog), findsNothing);
      expect(repo.sends, 2);
      expect(
        find.descendant(
          of: find.byType(ChatMessageBubble),
          matching: find.byType(CupertinoActivityIndicator),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byType(ChatMessageBubble));
      await tester.pump();
      expect(repo.sends, 2);
      repo.sending!.completeError(
        ApiError(message: 'Rejected again', statusCode: 422),
      );
      await tester.pumpAndSettle();
      expect(composer.state.localMessages.single.id, localId);
      expect(find.text('Failed to send. Tap to retry.'), findsOneWidget);
      repo.sending = null;
      await tester.tap(find.text('Failed to send. Tap to retry.'));
      await tester.pumpAndSettle();
      expect(repo.sends, 3);
      expect(composer.state.localMessages, isEmpty);
      expect(find.byType(ChatMessageBubble), findsOneWidget);
      expect(find.text('Failed to send. Tap to retry.'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'pre-send failure retries immediately without the Delivery unknown dialog',
    (tester) async {
      final repo = RetryRepo()
        ..messageItems = []
        ..rejection = ChatPreSendFailure();
      await tester.pumpWidget(
        harness(
          ConversationScreen(
            conversation: conversation,
            repository: repo,
            currentUserId: 'self',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'fixture');
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      expect(find.text('Failed to send. Tap to retry.'), findsOneWidget);
      expect(ChatPreSendFailure().message, isNot(contains('failed message')));
      repo.rejection = null;
      await tester.tap(find.text('Failed to send. Tap to retry.'));
      await tester.pumpAndSettle();
      expect(find.text('Delivery unknown'), findsNothing);
      expect(repo.sends, 2);
      expect(find.text('Failed to send. Tap to retry.'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'offline send clears the input immediately; one failed bubble; retry keeps one message',
    (tester) async {
      final repo = RetryRepo()
        ..messageItems = []
        ..rejection = ChatPreSendFailure();
      await tester.pumpWidget(
        harness(
          ConversationScreen(
            conversation: conversation,
            repository: repo,
            currentUserId: 'self',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Kkkkk');
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      final input = tester.widget<TextField>(find.byType(TextField));
      expect(input.controller!.text, isEmpty);
      expect(find.text('Kkkkk'), findsOneWidget); // the failed bubble only
      expect(find.text('Failed to send. Tap to retry.'), findsOneWidget);
      // Nothing left to resend from the composer: no second bubble possible.
      expect(find.byTooltip('Send message'), findsNothing);
      expect(repo.sends, 1);
      repo.rejection = null;
      await tester.tap(find.text('Failed to send. Tap to retry.'));
      await tester.pumpAndSettle();
      expect(repo.sends, 2);
      expect(find.text('Kkkkk'), findsOneWidget);
      expect(find.text('Failed to send. Tap to retry.'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'ambiguous retry refreshes first, warns only contextually and never resends on reconnect',
    (tester) async {
      final repo = RetryRepo()
        ..messageItems = []
        ..rejection = TimeoutException('fixture timeout');
      await tester.pumpWidget(
        harness(
          ConversationScreen(
            conversation: conversation,
            repository: repo,
            currentUserId: 'self',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'fixture');
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Send was not confirmed'), findsNothing);
      final histories = repo.histories;
      await tester.tap(find.text('Failed to send. Tap to retry.'));
      await tester.pumpAndSettle();
      expect(repo.histories, greaterThan(histories));
      expect(find.text('Delivery unknown'), findsOneWidget);
      expect(repo.sends, 1);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      connected = false;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      connected = true;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(repo.sends, 1);
      expect(find.text('Failed to send. Tap to retry.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'ambiguous known ID found in history removes local failure without sending again',
    (tester) async {
      final repo = RetryRepo()
        ..messageItems = []
        ..rejection = ChatUnconfirmedSend(serverMessageId: '123');
      await tester.pumpWidget(
        harness(
          ConversationScreen(
            conversation: conversation,
            repository: repo,
            currentUserId: 'self',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'fixture');
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      repo.messageItems = [
        ChatMessage(
          id: '123',
          senderId: 'self',
          conversationId: conversation.id,
          kind: ChatMessageKind.text,
          text: 'fixture',
        ),
      ];
      await tester.tap(find.text('Failed to send. Tap to retry.'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(repo.sends, 1);
      expect(find.byType(ChatMessageBubble), findsOneWidget);
      expect(find.text('Failed to send. Tap to retry.'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final reduced in [false, true]) {
    testWidgets(
      'bottom offline banner above composer/tray and keyboard; reduced=$reduced',
      (tester) async {
        tester.view.physicalSize = const Size(320, 650);
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = const FakeViewPadding(bottom: 220);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        connected = false;
        final repo = RetryRepo();
        final composer = ChatComposerCubit(
          repository: repo,
          conversation: conversation,
          onSent: (_) {},
        );
        final audio = ChatAudioController(),
            text = TextEditingController(text: 'draft');
        composer.edit('draft');
        await tester.pumpWidget(
          harness(
            Scaffold(
              body: MediaQuery(
                data: MediaQueryData(
                  size: const Size(320, 650),
                  disableAnimations: reduced,
                ),
                child: Column(
                  children: [
                    const Expanded(
                      child: Center(child: Text('Message history')),
                    ),
                    ChatComposer(
                      composer: composer,
                      text: text,
                      audio: audio,
                      canSend: true,
                      uploading: false,
                      topAccessory: ChatNetworkBanner(onReconnect: () async {}),
                      selectedMediaTray: const SizedBox(
                        key: ValueKey('fixture-tray'),
                        height: 50,
                        child: Text('Selected image'),
                      ),
                      onAttachment: () {},
                      onTyped: () {},
                      onSendVoice: () {},
                      onDiscardMedia: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final banner = find.byKey(const ValueKey('chat-offline-banner'));
        expect(
          tester.getBottomRight(banner).dy,
          lessThanOrEqualTo(
            tester.getTopLeft(find.byKey(const ValueKey('fixture-tray'))).dy,
          ),
        );
        expect(
          tester.getBottomRight(find.byType(TextField)).dy,
          lessThanOrEqualTo(430),
        );
        connected = null;
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(banner, findsOneWidget);
        connected = true;
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(banner, findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await composer.close();
        audio.dispose();
        text.dispose();
      },
    );
  }

  testWidgets(
    'actual conversation mounts offline banner below history rather than header',
    (tester) async {
      connected = false;
      final repo = RetryRepo();
      await tester.pumpWidget(
        harness(
          ConversationScreen(
            conversation: conversation,
            repository: repo,
            currentUserId: 'self',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final banner = find.byKey(const ValueKey('chat-offline-banner'));
      expect(
        tester.getTopLeft(banner).dy,
        greaterThan(tester.getBottomRight(find.byType(ChatMessageBubble)).dy),
      );
      expect(
        tester.getBottomRight(banner).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(TextField)).dy),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'emoji picker inserts at selection, toggles keyboard, survives draft and hides across navigation/session switch',
    (tester) async {
      final repo = RetryRepo();
      final composer = ChatComposerCubit(
        repository: repo,
        conversation: conversation,
        onSent: (_) {},
      );
      final audio = ChatAudioController(),
          text = TextEditingController(text: 'Hello world');
      composer.edit(text.text);
      Widget composerWidget() => ChatComposer(
        composer: composer,
        text: text,
        audio: audio,
        canSend: true,
        uploading: false,
        onAttachment: () {},
        onTyped: () {},
        onSendVoice: () {},
        onDiscardMedia: () {},
      );
      await tester.pumpWidget(
        harness(
          Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: composerWidget(),
            ),
          ),
        ),
      );
      text.selection = const TextSelection.collapsed(offset: 5);
      await tester.tap(find.byTooltip('Show emoji picker'));
      await tester.pumpAndSettle();
      expect(find.byType(EmojiPicker), findsOneWidget);
      await tester.tap(find.text('😀').first);
      await tester.pump();
      expect(text.text, 'Hello😀 world');
      expect(composer.state.draft, text.text);
      text.selection = TextSelection(
        baseOffset: 0,
        extentOffset: text.text.length,
      );
      tester.widget<EmojiPicker>(find.byType(EmojiPicker)).onEmojiSelected!(
        null,
        const Emoji('👩🏽‍💻', 'technologist'),
      );
      await tester.pump();
      expect(text.text, '👩🏽‍💻');
      expect(text.selection.baseOffset, text.text.length);
      await tester.tap(find.byTooltip('Show keyboard'));
      await tester.pumpAndSettle();
      expect(find.byType(EmojiPicker), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).keyboardType,
        TextInputType.multiline,
      );
      await tester.tap(find.byTooltip('Show emoji picker'));
      await tester.pumpAndSettle();
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Other route')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EmojiPicker, skipOffstage: false), findsNothing);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(text.text, '👩🏽‍💻');
      await tester.tap(find.byTooltip('Show emoji picker'));
      await tester.pumpAndSettle();
      final callback = tester
          .widget<EmojiPicker>(find.byType(EmojiPicker))
          .onEmojiSelected!;
      await prefs.saveToken('new-account');
      await tester.pumpAndSettle();
      expect(find.byType(EmojiPicker), findsNothing);
      expect(text.text, isEmpty);
      callback(null, const Emoji('😀', 'grin'));
      expect(text.text, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await composer.close();
      audio.dispose();
      text.dispose();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'emoji picker and tray fit a small landscape viewport with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 430);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final composer = ChatComposerCubit(
        repository: RetryRepo(),
        conversation: conversation,
        onSent: (_) {},
      );
      final audio = ChatAudioController(), text = TextEditingController();
      await tester.pumpWidget(
        harness(
          Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ChatComposer(
                composer: composer,
                text: text,
                audio: audio,
                canSend: true,
                uploading: false,
                selectedMediaTray: const SizedBox(
                  height: 70,
                  child: Text('Selected image'),
                ),
                onAttachment: () {},
                onTyped: () {},
                onSendVoice: () {},
                onDiscardMedia: () {},
              ),
            ),
          ),
          scale: 1.5,
        ),
      );
      await tester.tap(find.byTooltip('Show emoji picker'));
      await tester.pumpAndSettle();
      expect(find.byType(EmojiPicker), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await composer.close();
      audio.dispose();
      text.dispose();
    },
  );
  testWidgets(
    'native keyboard metrics reveal emoji picker only after keyboard dismissal',
    (tester) async {
      final composer = ChatComposerCubit(
        repository: RetryRepo(),
        conversation: conversation,
        onSent: (_) {},
      );
      final audio = ChatAudioController(), text = TextEditingController();
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        harness(
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
                onSendVoice: () {},
                onDiscardMedia: () {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Show emoji picker'));
      await tester.pumpAndSettle();
      expect(find.byType(EmojiPicker), findsNothing);
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      expect(find.byType(EmojiPicker), findsOneWidget);
      await tester.tap(find.byTooltip('Show keyboard'));
      await tester.pumpAndSettle();
      expect(find.byType(EmojiPicker), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await composer.close();
      audio.dispose();
      text.dispose();
    },
  );

  testWidgets(
    'banner transitions retain conversation scroll offset while reading older history',
    (tester) async {
      final repo = RetryRepo()
        ..messageItems = List.generate(
          50,
          (i) => ChatMessage(
            id: '$i',
            senderId: 'other',
            kind: ChatMessageKind.text,
            text: 'History fixture $i',
          ),
        );
      await tester.pumpWidget(
        harness(
          ConversationScreen(
            conversation: conversation,
            repository: repo,
            currentUserId: 'self',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final controller = tester
          .widget<ListView>(find.byType(ListView))
          .controller!;
      controller.jumpTo(200);
      await tester.pump();
      final before = controller.offset;
      connected = false;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(before, .5));
      connected = true;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(before, .5));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'audio errors remain visible without resurrecting persistent ambiguous-send warnings',
    (tester) async {
      final repo = RetryRepo()..rejection = TimeoutException('fixture');
      final composer = ChatComposerCubit(
        repository: repo,
        conversation: conversation,
        onSent: (_) {},
      );
      composer.edit('fixture');
      await composer.send();
      final audio = ChatAudioController()..error = 'Microphone unavailable';
      final text = TextEditingController(text: 'fixture');
      await tester.pumpWidget(
        harness(
          Scaffold(
            body: ChatComposer(
              composer: composer,
              text: text,
              audio: audio,
              canSend: true,
              uploading: false,
              onAttachment: () {},
              onTyped: () {},
              onSendVoice: () {},
              onDiscardMedia: () {},
            ),
          ),
        ),
      );
      expect(find.text('Microphone unavailable'), findsOneWidget);
      expect(find.textContaining('Send was not confirmed'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await composer.close();
      audio.dispose();
      text.dispose();
    },
  );
}
