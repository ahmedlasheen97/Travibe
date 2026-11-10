import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/screens/chats_screen.dart';
import 'package:travibe/features/chats/screens/conversation_screen.dart';
import 'package:travibe/features/chats/widgets/chat_widgets.dart';
import 'chat_fakes.dart';
import 'package:travibe/features/chats/cubit/chat_audio_controller.dart';
import 'package:travibe/features/chats/cubit/chat_cubit.dart';
import 'package:travibe/features/chats/widgets/chat_composer.dart';
import 'dart:typed_data';
import 'package:travibe/features/chats/widgets/chat_video_message.dart';
import 'package:video_player/video_player.dart';
import 'package:travibe/features/chats/data/chat_repository.dart';

Widget harness(
  Widget child, {
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
}) => ScreenUtilInit(
  designSize: const Size(390, 844),
  builder: (_, _) => MaterialApp(
    theme: ThemeData.dark().copyWith(
      scaffoldBackgroundColor: const Color(0xFF080808),
    ),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: Directionality(textDirection: direction, child: child),
      ),
    ),
  ),
);
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('test-session');
  });
  testWidgets(
    'voice draft and composer remain scrollable above a landscape keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(320, 430);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final audio = ChatAudioController()
        ..draft = ChatVoiceDraft(Uint8List.fromList([1]), 1000);
      final composer = ChatComposerCubit(
        repository: FakeChatRepository(),
        conversation: conversation,
        onSent: (_) {},
      );
      final text = TextEditingController(
        text: 'Draft line 1\nDraft line 2\nDraft line 3',
      );
      composer.edit(text.text);
      await tester.pumpWidget(
        harness(
          Scaffold(
            body: Column(
              children: [
                const SizedBox(height: 70),
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
                  mediaError:
                      'A retryable attachment error remains visible without covering the keyboard.',
                ),
              ],
            ),
          ),
          scale: 1.6,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byType(TextField));
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
  testWidgets(
    'detail GET updates existing header without inferred read mutation',
    (tester) async {
      final repo = _DetailsRepo();
      await tester.pumpWidget(
        harness(
          ConversationScreen(repository: repo, conversation: conversation),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Server participant'), findsOneWidget);
      expect(repo.detailLoads, 1);
      expect(repo.reads, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('detail failure exposes retry and recovers', (tester) async {
    final repo = _DetailsRepo()..failDetail = true;
    await tester.pumpWidget(
      harness(ConversationScreen(repository: repo, conversation: conversation)),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to load this conversation. Please retry.'),
      findsOneWidget,
    );
    repo.failDetail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(repo.detailLoads, 2);
    expect(find.text('Server participant'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('late detail result cannot expose previous account participant', (
    tester,
  ) async {
    final repo = _DetailsRepo()..detailsPending = Completer();
    await tester.pumpWidget(
      harness(ConversationScreen(repository: repo, conversation: conversation)),
    );
    await tester.pump();
    await PreferencesManager().saveToken('replacement-account');
    repo.detailsPending!.complete(_serverConversation);
    await tester.pumpAndSettle();
    expect(find.text('Server participant'), findsNothing);
    expect(find.text('Sign in again to use messaging.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'requests use server total rather than count of the loaded page',
    (tester) async {
      final repo = _RequestTotalRepo();
      await tester.pumpWidget(harness(ChatsScreen(repository: repo)));
      await tester.pumpAndSettle();
      expect(find.text('Requests (31)'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('inbox shows server-backed participant, unread and preview', (
    tester,
  ) async {
    final repo = FakeChatRepository()
      ..items = [
        const ChatConversation(
          id: '1',
          participant: participant,
          preview: 'Test preview',
          unread: 3,
        ),
      ];
    await tester.pumpWidget(harness(ChatsScreen(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('Test Person'), findsOneWidget);
    expect(find.text('Test preview'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Requests (1)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('local case-insensitive search and clear do not reload API', (
    tester,
  ) async {
    final repo = FakeChatRepository();
    await tester.pumpWidget(harness(ChatsScreen(repository: repo)));
    await tester.pumpAndSettle();
    final count = repo.loads;
    await tester.enterText(find.byType(TextField), 'TEST PERSON');
    await tester.pump();
    expect(find.text('Test Person'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'not present');
    await tester.pump();
    expect(find.text('No Results Found'), findsOneWidget);
    expect(repo.loads, count);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(find.text('Test Person'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('initial loading uses dark skeleton; cached refresh keeps rows', (
    tester,
  ) async {
    final repo = FakeChatRepository()..loading = Completer();
    await tester.pumpWidget(harness(ChatsScreen(repository: repo)));
    await tester.pump();
    expect(find.byType(ChatsLoadingSkeleton), findsOneWidget);
    repo.loading!.complete(ChatPage([conversation]));
    repo.loading = null;
    await tester.pumpAndSettle();
    expect(find.byType(ChatsLoadingSkeleton), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'production unavailable state offers retry without fabricated rows',
    (tester) async {
      await tester.pumpWidget(
        harness(ChatsScreen(repository: LaravelChatRepository(contract: null))),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Messaging is not available'), findsOneWidget);
      expect(find.text('Test Person'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Messaging is not available'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('own-account content disappears immediately on account change', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(ChatsScreen(repository: FakeChatRepository())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Test Person'), findsOneWidget);
    await PreferencesManager().saveToken('replacement');
    await tester.pump();
    expect(find.text('Test Person'), findsNothing);
    expect(find.text('Sign in again to use messaging.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('request accept uses existing conversation action and refresh', (
    tester,
  ) async {
    final repo = FakeChatRepository();
    await tester.pumpWidget(
      harness(ChatsScreen(repository: repo, requests: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Accept'), findsNothing);
    await tester.tap(find.text('Test Person'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(repo.accepts, 1);
    expect(find.byType(ChatComposer), findsOneWidget);
    Navigator.of(tester.element(find.byType(ConversationScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.text('No message requests'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('conversation sending text clears input after success', (
    tester,
  ) async {
    final repo = FakeChatRepository();
    await tester.pumpWidget(
      harness(
        ConversationScreen(
          repository: repo,
          conversation: conversation,
          currentUserId: 'self',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sent'), findsNothing);
    await tester.tap(find.text('Test message'));
    await tester.pump();
    expect(find.text('Sent'), findsOneWidget);
    expect(find.text('Delivered'), findsNothing);
    expect(find.text('Seen'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(repo.sends, 1);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('attachment menu explicitly disables unsupported uploads', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        ConversationScreen(
          repository: FakeChatRepository(),
          conversation: conversation,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Attachments'));
    await tester.pumpAndSettle();
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Gallery'), findsOneWidget);
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, 'Camera')).enabled,
      false,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('voice message never simulates playback', (tester) async {
    await tester.pumpWidget(
      harness(
        const Scaffold(body: ChatVoiceMessage(duration: Duration(seconds: 16))),
      ),
    );
    expect(find.text('0:16'), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
  });
  for (final width in [320.0, 375.0, 393.0, 430.0, 844.0]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('chat inbox and composer fit width $width scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, width == 844 ? 430 : 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          harness(ChatsScreen(repository: FakeChatRepository()), scale: scale),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          harness(
            ConversationScreen(
              repository: FakeChatRepository(),
              conversation: conversation,
              currentUserId: 'self',
            ),
            scale: scale,
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField),
          'Long draft 😀\nمرحبا بالعالم\nAnother line',
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
  testWidgets(
    'RTL long unicode message wraps in the real conversation scrollable',
    (tester) async {
      final repo = FakeChatRepository()
        ..messageItems = [
          ChatMessage(
            id: '101',
            senderId: 'other',
            kind: ChatMessageKind.text,
            text: List.filled(20, 'مرحبا 😀 hello\n').join(),
          ),
        ];
      await tester.pumpWidget(
        harness(
          ConversationScreen(
            repository: repo,
            conversation: conversation,
            currentUserId: 'self',
          ),
          direction: TextDirection.rtl,
          scale: 1.6,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'video does not autoplay or load URLs and hides on account change',
    (tester) async {
      await tester.pumpWidget(
        harness(
          Scaffold(
            body: ChatVideoMessage(
              url: Uri.parse('https://example.invalid/video.mp4'),
            ),
          ),
        ),
      );
      expect(find.byType(VideoPlayer), findsNothing);
      expect(find.byTooltip('Play video'), findsOneWidget);
      await PreferencesManager().saveToken('replacement');
      await tester.pump();
      expect(find.text('Video unavailable'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('missing actor avatar uses existing fallback', (tester) async {
    await tester.pumpWidget(
      harness(
        Scaffold(
          body: ChatListTile(conversation: conversation, onTap: () {}),
        ),
      ),
    );
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    expect(find.text('Online'), findsNothing);
  });
}

const _serverConversation = ChatConversation(
  id: 'conversation-1',
  participant: ChatParticipant(id: 'other', name: 'Server participant'),
);

class _DetailsRepo extends FakeChatRepository
    implements ConversationDetailsRepository {
  _DetailsRepo() {
    capabilities = const ChatCapabilities(
      list: true,
      messages: true,
      detail: true,
    );
  }
  int detailLoads = 0;
  bool failDetail = false;
  Completer<ChatConversation>? detailsPending;
  @override
  Future<ChatConversation> conversation(String id) async {
    detailLoads++;
    if (failDetail) throw Exception('fixture failure');
    return detailsPending?.future ?? Future.value(_serverConversation);
  }
}

class _RequestTotalRepo extends FakeChatRepository {
  @override
  Future<ChatPage<ChatConversation>> conversations({
    String? continuation,
    bool requests = false,
  }) async => ChatPage([conversation], continuation: '2', total: 31);
}
