import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/chats/cubit/chat_cubit.dart';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/data/chat_repository.dart';
import 'package:travibe/features/chats/data/chat_reverb_service.dart';
import 'package:travibe/features/chats/screens/chats_screen.dart';
import 'package:travibe/features/chats/screens/conversation_screen.dart';
import 'package:travibe/features/chats/widgets/chat_composer.dart';
import 'package:travibe/features/chats/widgets/chat_request_controls.dart';
import 'package:travibe/features/chats/widgets/chat_reverb_host.dart';
import 'package:travibe/features/chats/widgets/chat_widgets.dart';
import 'chat_fakes.dart';

Widget requestApp(Widget child, {double scale = 1}) => ScreenUtilInit(
  designSize: const Size(390, 844),
  builder: (_, _) => MaterialApp(
    theme: darkTheme,
    debugShowCheckedModeBanner: false,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: child,
  ),
);

const pending = ChatConversation(
  id: '42',
  participant: ChatParticipant(id: '7', name: 'Request Person'),
  isAccepted: false,
  isBlocked: false,
  unread: 2,
  preview: 'Hello there',
);
const accepted = ChatConversation(
  id: '42',
  participant: ChatParticipant(id: '7', name: 'Request Person'),
  isAccepted: true,
  isBlocked: false,
  canSend: true,
  preview: 'Hello there',
);

class RequestsRepo extends FakeChatRepository
    implements ChatOperationsRepository {
  RequestsRepo() {
    capabilities = const ChatCapabilities(
      list: true,
      messages: true,
      detail: true,
      requests: true,
      requestActions: true,
      read: true,
      sendText: true,
      attachments: true,
    );
    messageItems = [
      const ChatMessage(
        id: '101',
        senderId: '7',
        kind: ChatMessageKind.text,
        text: 'Incoming request history',
        createdAt: null,
      ),
    ];
  }
  bool isAccepted = false, isDeclined = false, fail = false;
  Completer<void>? mutation;
  Completer<ChatConversation>? detailsGate;
  Completer<void>? nextCountGate;
  final List<bool> typingEvents = [];
  ChatConversation get current => isAccepted ? accepted : pending;
  @override
  Future<ChatPage<ChatConversation>> conversations({
    String? continuation,
    bool requests = false,
  }) async {
    loads++;
    final values = requests
        ? (!isAccepted && !isDeclined ? [pending] : <ChatConversation>[])
        : (isAccepted ? [accepted] : <ChatConversation>[]);
    final gate = requests ? nextCountGate : null;
    if (gate != null) {
      nextCountGate = null;
      await gate.future;
    }
    return ChatPage(values, total: values.length);
  }

  @override
  Future<ChatConversation> conversation(String id) async =>
      detailsGate?.future ?? current;
  @override
  Future<ChatConversation> acceptRequest(String id) async {
    accepts++;
    if (mutation != null) await mutation!.future;
    if (fail) throw ApiError(message: 'Unavailable');
    isAccepted = true;
    return accepted;
  }

  @override
  Future<void> resolveRequest(String id, {required bool accept}) async {
    if (accept) {
      await acceptRequest(id);
      return;
    }
    declines++;
    if (mutation != null) await mutation!.future;
    if (fail) throw ApiError(message: 'Unavailable');
    isDeclined = true;
  }

  @override
  Future<ChatConversation> readConversation(String id) async {
    reads++;
    return current;
  }

  @override
  Future<void> typing(String id, bool value) async {
    typingEvents.add(value);
  }

  @override
  Future<ChatPage<ChatMessage>> messageChanges(
    String id, {
    String? afterId,
    DateTime? updatedSince,
    String? continuation,
  }) async => ChatPage([]);
  @override
  Future<ChatConversation> setMuted(String id, bool muted) async => current;
  @override
  Future<ChatMessage> reply(String id, String text, String replyToId) =>
      sendText(id, text);
  @override
  Future<ChatMessage> sendPost(String id, int postId) async => message;
  @override
  Future<ChatMessage> sendMedia(
    String id, {
    required ChatMessageKind kind,
    required int mediaId,
    String? caption,
    int? durationMs,
    int? posterMediaId,
    String? replyToId,
  }) async => message;
  @override
  Future<void> deleteMessage(String messageId) async {}
}

class RequestsReverb extends ChatReverbService {
  final hints = StreamController<ChatReverbSignal>.broadcast();
  final List<ChatConversation> bound = [];
  @override
  Stream<ChatReverbSignal> get signals => hints.stream;
  @override
  void conversation(Object owner, ChatConversation? value) {
    if (value != null) bound.add(value);
  }

  @override
  void dispose() {
    hints.close();
    super.dispose();
  }
}

Finder action(String label) => find.widgetWithText(ChatRequestButton, label);

void main() {
  final preferences = PreferencesManager();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.saveToken('requests-fixture');
  });
  tearDown(() async => preferences.clear());

  Future<void> openRequests(
    WidgetTester tester,
    RequestsRepo repo, {
    RequestsReverb? reverb,
  }) async {
    final app = requestApp(ChatsScreen(repository: repo));
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('requests-render'),
        child: reverb == null
            ? app
            : ChatReverbScope(service: reverb, child: app),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Requests (1)'));
    await tester.pumpAndSettle();
  }

  Future<void> openPending(
    WidgetTester tester,
    RequestsRepo repo, {
    RequestsReverb? reverb,
  }) async {
    await openRequests(tester, repo, reverb: reverb);
    await tester.tap(find.text('Request Person'));
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    final context = tester.element(find.byType(Scaffold).last);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CHAT_CAPTURE')) return;
    await tester.pump(const Duration(milliseconds: 250));
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('requests-render')),
      );
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '/private/tmp/travibe-requests-$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'request list, pending conversation, confirmation and declined state render consistently',
    (tester) async {
      if (const bool.fromEnvironment('CHAT_CAPTURE')) {
        await tester.runAsync(() async {
          final font = FontLoader('Plus Jakarta Sans')
            ..addFont(
              rootBundle.load('assets/fonts/PlusJakartaSans-Regular.ttf'),
            );
          final icons = FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await font.load();
          await icons.load();
        });
      }
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = RequestsRepo();
      await openRequests(tester, repo);
      expect(find.byType(TextField), findsNothing);
      await capture(tester, 'list');
      await tester.tap(find.text('Request Person'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatComposer), findsNothing);
      await capture(tester, 'pending');
      await tester.tap(action('Decline'));
      await tester.pumpAndSettle();
      expect(find.text('Decline message request?'), findsOneWidget);
      await capture(tester, 'confirmation');
      final confirm = find.descendant(
        of: find.byType(ChatDeclineRequestDialog),
        matching: find.widgetWithText(TextButton, 'Decline'),
      );
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.text('No message requests'), findsOneWidget);
      expect(find.text('Requests'), findsOneWidget);
      await capture(tester, 'declined');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Requests list is compact, centered and has no search or inline actions',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final repo = RequestsRepo();
        await openRequests(tester, repo);
        expect(find.text('Requests'), findsOneWidget);
        expect(find.text('Message Requests'), findsNothing);
        expect(find.byType(TextField), findsNothing);
        expect(action('Accept'), findsNothing);
        expect(action('Decline'), findsNothing);
        expect(find.byType(ChatListTile), findsOneWidget);
        expect(tester.getSize(find.byType(ChatListTile)).height, lessThan(110));
        expect(
          tester.getCenter(find.text('Requests')).dx,
          closeTo(tester.getCenter(find.byType(Scaffold).last).dx, 1),
        );
        expect(find.text('Hello there'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
        expect(
          find.bySemanticsLabel(RegExp('2 unread messages')),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'pending recipient has no composer, typing or presence subscription',
    (tester) async {
      final repo = RequestsRepo();
      final reverb = RequestsReverb();
      await openPending(tester, repo, reverb: reverb);
      expect(find.text('Incoming request history'), findsOneWidget);
      expect(find.text('Accept request to reply'), findsOneWidget);
      expect(find.byType(ChatComposer), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byTooltip('Attachments'), findsNothing);
      expect(repo.typingEvents, isEmpty);
      expect(reverb.bound, isEmpty);
      expect(repo.sends, 0);
      await tester.pumpWidget(const SizedBox());
      reverb.dispose();
    },
  );

  testWidgets(
    'accept waits for server, locks taps, enables composer, rereads and synchronizes inbox/count',
    (tester) async {
      final repo = RequestsRepo()..mutation = Completer();
      final reverb = RequestsReverb();
      await openPending(tester, repo, reverb: reverb);
      final target = tester.getCenter(action('Accept'));
      await tester.tapAt(target);
      await tester.pump();
      await tester.tapAt(target);
      await tester.pump();
      expect(repo.accepts, 1);
      expect(find.byType(ChatComposer), findsNothing);
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(reverb.bound, isEmpty);
      repo.mutation!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ChatComposer), findsOneWidget);
      expect(find.text('Incoming request history'), findsOneWidget);
      expect(find.text('Accept request to reply'), findsNothing);
      expect(repo.reads, greaterThanOrEqualTo(2));
      expect(reverb.bound.any((item) => item.isAccepted == true), isTrue);
      await back(tester);
      expect(find.text('No message requests'), findsOneWidget);
      await back(tester);
      expect(find.text('Requests'), findsOneWidget);
      expect(find.text('Request Person'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      reverb.dispose();
    },
  );

  testWidgets(
    'accept failure preserves history and request, then allows explicit retry',
    (tester) async {
      final repo = RequestsRepo()..fail = true;
      await openPending(tester, repo);
      await tester.tap(action('Accept'));
      await tester.pumpAndSettle();
      expect(repo.accepts, 1);
      expect(find.textContaining('Unable to accept'), findsOneWidget);
      expect(find.text('Incoming request history'), findsOneWidget);
      expect(find.byType(ChatComposer), findsNothing);
      repo.fail = false;
      await tester.tap(action('Accept'));
      await tester.pumpAndSettle();
      expect(repo.accepts, 2);
      expect(find.byType(ChatComposer), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('decline Cancel closes confirmation without an API mutation', (
    tester,
  ) async {
    final repo = RequestsRepo();
    await openPending(tester, repo);
    await tester.tap(action('Decline'));
    await tester.pumpAndSettle();
    expect(find.text('Decline message request?'), findsOneWidget);
    expect(
      find.text('This request will be removed from your requests.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(repo.declines, 0);
    expect(find.byType(ConversationScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final failure in [false, true]) {
    testWidgets(
      'decline locks duplicate taps; failure=$failure preserves state and supports retry',
      (tester) async {
        final repo = RequestsRepo()
          ..mutation = Completer()
          ..fail = failure;
        await openPending(tester, repo);
        await tester.tap(action('Decline'));
        await tester.pumpAndSettle();
        final confirm = find.descendant(
          of: find.byType(ChatDeclineRequestDialog),
          matching: find.widgetWithText(TextButton, 'Decline'),
        );
        final target = tester.getCenter(confirm);
        await tester.tapAt(target);
        await tester.pump();
        await tester.tapAt(target);
        await tester.pump();
        expect(repo.declines, 1);
        expect(find.byType(ChatDeclineRequestDialog), findsOneWidget);
        repo.mutation!.complete();
        await tester.pumpAndSettle();
        if (failure) {
          expect(find.textContaining('Unable to decline'), findsOneWidget);
          expect(repo.isDeclined, false);
          repo.fail = false;
          repo.mutation = null;
          await tester.tap(confirm);
          await tester.pumpAndSettle();
          expect(repo.declines, 2);
        }
        expect(find.byType(ConversationScreen), findsNothing);
        expect(find.text('No message requests'), findsOneWidget);
        expect(find.text('Message request declined'), findsOneWidget);
        await back(tester);
        expect(find.text('Requests'), findsOneWidget);
        expect(find.text('Request Person'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'account switch during acceptance ignores late response and clears private history',
    (tester) async {
      final repo = RequestsRepo()..mutation = Completer();
      await openPending(tester, repo);
      await tester.tap(action('Accept'));
      await tester.pump();
      await preferences.saveToken('replacement-session');
      await tester.pump();
      repo.mutation!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ChatComposer), findsNothing);
      expect(find.text('Incoming request history'), findsNothing);
      expect(find.text('Sign in again to use messaging.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'account switch dismisses decline dialog and ignores late mutation',
    (tester) async {
      final repo = RequestsRepo()..mutation = Completer();
      await openPending(tester, repo);
      await tester.tap(action('Decline'));
      await tester.pumpAndSettle();
      final confirm = find.descendant(
        of: find.byType(ChatDeclineRequestDialog),
        matching: find.widgetWithText(TextButton, 'Decline'),
      );
      await tester.tap(confirm);
      await tester.pump();
      await preferences.saveToken('replacement-session');
      await tester.pumpAndSettle();
      expect(find.byType(ChatDeclineRequestDialog), findsNothing);
      repo.mutation!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Message request declined'), findsNothing);
      expect(find.text('Sign in again to use messaging.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'reconnect REST acceptance promotes the conversation without another accept call',
    (tester) async {
      final repo = RequestsRepo();
      final reverb = RequestsReverb();
      await openPending(tester, repo, reverb: reverb);
      repo.isAccepted = true;
      reverb.hints.add(
        ChatReverbSignal('reconcile', preferences.sessionRevision),
      );
      await tester.pumpAndSettle();
      expect(repo.accepts, 0);
      expect(find.byType(ChatComposer), findsOneWidget);
      await back(tester);
      expect(find.text('No message requests'), findsOneWidget);
      await back(tester);
      expect(find.text('Requests'), findsOneWidget);
      expect(find.text('Request Person'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      reverb.dispose();
    },
  );

  testWidgets('stale pending details cannot overwrite a confirmed acceptance', (
    tester,
  ) async {
    final repo = RequestsRepo()..detailsGate = Completer();
    await openRequests(tester, repo);
    await tester.tap(find.text('Request Person'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(action('Accept'));
    await tester.pump();
    repo.detailsGate!.complete(pending);
    await tester.pumpAndSettle();
    expect(find.byType(ChatComposer), findsOneWidget);
    expect(find.text('Accept request to reply'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('late request-count response cannot undo confirmed acceptance', (
    tester,
  ) async {
    final repo = RequestsRepo();
    await tester.pumpWidget(requestApp(ChatsScreen(repository: repo)));
    await tester.pumpAndSettle();
    final gate = repo.nextCountGate = Completer();
    final refresh = tester
        .widget<CupertinoSliverRefreshControl>(
          find.byType(CupertinoSliverRefreshControl, skipOffstage: false),
        )
        .onRefresh!();
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Requests (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request Person'));
    await tester.pumpAndSettle();
    await tester.tap(action('Accept'));
    await tester.pumpAndSettle();
    gate.complete();
    await refresh;
    await tester.pumpAndSettle();
    await back(tester);
    await back(tester);
    expect(find.text('Requests'), findsOneWidget);
    expect(find.text('Request Person'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(requestApp(ChatsScreen(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('Requests'), findsOneWidget);
    expect(find.text('Request Person'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'confirmed removal cannot be resurrected by old pages, fresh snapshots or events; account resets it',
    () async {
      final gate = Completer<ChatPage<ChatConversation>>();
      final cubit = ChatListCubit<ChatConversation>(
        fetch: (_) => gate.future,
        idOf: (item) => item.id,
        cancel: () {},
      );
      final loading = cubit.load();
      cubit.removeConfirmed('42', session: preferences.sessionRevision);
      gate.complete(ChatPage([pending]));
      await loading;
      cubit.appendConfirmed(pending, session: preferences.sessionRevision);
      expect(cubit.state.items, isEmpty);
      await cubit.load();
      expect(cubit.state.items, isEmpty);
      await preferences.saveToken('replacement-session');
      await cubit.load();
      expect(cubit.state.items.single.id, '42');
      await cubit.close();
    },
  );

  for (final reduced in [false, true]) {
    testWidgets('glass button press/release and reduced motion=$reduced', (
      tester,
    ) async {
      int calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 180,
                  child: ChatRequestButton(
                    label: 'Accept',
                    onPressed: () => calls++,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Accept')),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(scale.scale, reduced ? 1 : .97);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
      expect(calls, 1);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 180,
              child: ChatRequestButton(
                label: 'Accept',
                loading: true,
                onPressed: () => calls++,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      await tester.tapAt(tester.getCenter(find.byType(ChatRequestButton)));
      await tester.pump();
      expect(calls, 1);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final width in [320.0, 375.0, 393.0, 430.0]) {
    testWidgets(
      'pending controls and dialog fit $width with safe area and enlarged text',
      (tester) async {
        tester.view.physicalSize = Size(width, 560);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
        tester.view.viewInsets = const FakeViewPadding(bottom: 120);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        addTearDown(tester.view.resetViewInsets);
        final repo = RequestsRepo();
        await tester.pumpWidget(
          requestApp(
            ConversationScreen(
              conversation: pending,
              repository: repo,
              receivedRequest: true,
            ),
            scale: 1.6,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byType(ChatRequestButton).first).height,
          greaterThanOrEqualTo(48),
        );
        expect(
          tester.getBottomRight(find.byType(ChatRequestButton).first).dy,
          lessThanOrEqualTo(440),
        );
        await tester.tap(action('Decline'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();
        expect(find.byType(ChatDeclineRequestDialog), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
