import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/screens/chats_screen.dart';
import 'package:travibe/features/chats/screens/conversation_screen.dart';
import 'package:travibe/features/chats/widgets/chat_widgets.dart';
import 'package:travibe/features/chats/screens/new_conversation_screen.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'chat_fakes.dart';

/// Capture opt-in test fixtures, never production rows or a live account.
const capture = bool.fromEnvironment('CHAT_CAPTURE');
final boundary = GlobalKey();
Future<void> show(
  WidgetTester tester,
  Widget child, {
  double width = 390,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, _) => RepaintBoundary(
        key: boundary,
        child: MaterialApp(
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
      ),
    ),
  );
  await tester.pump();
}

Future<void> captureFrame(WidgetTester tester, String name) async {
  if (!capture) return;
  await tester.pump(const Duration(milliseconds: 250));
  await tester.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await render.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '/private/tmp/travibe-chat-$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('reference-test');
  });
  Future<void> fonts(WidgetTester tester) async {
    if (!capture) return;
    await tester.runAsync(() async {
      final loader = FontLoader('Plus Jakarta Sans');
      loader.addFont(
        rootBundle.load('assets/fonts/PlusJakartaSans-Regular.ttf'),
      );
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });
  }

  testWidgets(
    'reference inbox and search renders use real widgets and loaded test data',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      await fonts(tester);
      final repo = FakeChatRepository()
        ..items = List.generate(
          8,
          (i) => ChatConversation(
            id: '${i + 1}',
            participant: ChatParticipant(
              id: '${i + 2}',
              name: 'Traveler ${i + 1}',
            ),
            preview: 'A message from a test conversation',
            unread: i == 0 ? 2 : 0,
            lastMessageAt: DateTime.now().subtract(
              Duration(minutes: 24 + i * 35),
            ),
          ),
        );
      await show(tester, ChatsScreen(repository: repo));
      await tester.pumpAndSettle();
      await captureFrame(tester, 'inbox');
      await tester.enterText(find.byType(TextField), 'Traveler 1');
      await tester.pump();
      expect(find.text('Messages'), findsNothing);
      expect(find.text('Chats'), findsNWidgets(2));
      expect(find.textContaining('Requests ('), findsNothing);
      await captureFrame(tester, 'search');
      await tester.enterText(find.byType(TextField), 'absent person');
      await tester.pump();
      await captureFrame(tester, 'empty-search');
      expect(find.text('No Results Found'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('reference initial skeleton renders without sample rows', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    final repo = FakeChatRepository()..loading = Completer();
    await show(tester, ChatsScreen(repository: repo));
    expect(find.byType(ChatsLoadingSkeleton), findsOneWidget);
    expect(find.text('Messages'), findsNothing);
    expect(find.textContaining('Requests'), findsNothing);
    await captureFrame(tester, 'skeleton');
    await tester.pumpWidget(const SizedBox());
    repo.loading!.complete(ChatPage<ChatConversation>([]));
  });
  testWidgets(
    'reference conversation and attachment renders retain message data',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      await fonts(tester);
      final repo = FakeChatRepository()
        ..messageItems = [
          ChatMessage(
            id: '1',
            senderId: '2',
            kind: ChatMessageKind.text,
            text: 'Hello!\nA multiline message from a test conversation.',
            createdAt: DateTime.now(),
          ),
          ChatMessage(
            id: '2',
            senderId: 'self',
            kind: ChatMessageKind.text,
            text: 'A reply from the current test account.',
            createdAt: DateTime.now(),
          ),
          ChatMessage(
            id: '3',
            senderId: '2',
            kind: ChatMessageKind.audio,
            duration: const Duration(seconds: 16),
            createdAt: DateTime.now(),
          ),
        ];
      repo.capabilities = const ChatCapabilities(
        messages: true,
        sendText: true,
        remove: true,
        attachments: true,
      );
      await show(
        tester,
        ConversationScreen(
          repository: repo,
          conversation: conversation,
          currentUserId: 'self',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).decoration!.filled,
        false,
      );
      expect(
        tester.getTopLeft(find.textContaining('Hello!')).dy,
        lessThan(300),
      );
      await captureFrame(tester, 'conversation');
      final anchor = tester.getRect(find.byTooltip('Attachments'));
      await tester.tap(find.byTooltip('Attachments'));
      await tester.pumpAndSettle();
      await captureFrame(tester, 'attachments');
      expect(find.text('Camera'), findsOneWidget);
      final menu = tester.getRect(find.byType(ChatAttachmentMenu));
      expect(menu.width, lessThan(230));
      expect(menu.bottom, lessThan(anchor.top));
      expect(menu.left, greaterThanOrEqualTo(16));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Chats to New Conversation preserves shared owners and Back retains inbox',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      final follow = FollowCubit();
      final block = BlockCubit(follow: follow);
      final repo = FakeChatRepository();
      await show(
        tester,
        MultiBlocProvider(
          providers: [
            BlocProvider.value(value: follow),
            BlocProvider.value(value: block),
          ],
          child: ChatsScreen(repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      final open = tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton && widget.tooltip == 'New conversation',
            ),
          )
          .onPressed!;
      open();
      open();
      await tester.pumpAndSettle();
      expect(find.byType(NewConversationScreen), findsOneWidget);
      expect(
        tester.element(find.byType(NewConversationScreen)).read<FollowCubit>(),
        same(follow),
      );
      expect(
        find.text('Enter 3–100 characters to find people.'),
        findsOneWidget,
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration!.fillColor, const Color(0xFF141414));
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatsScreen), findsOneWidget);
      expect(find.text('Test Person'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await block.close();
      await follow.close();
    },
  );

  testWidgets(
    'existing conversation Back retains inbox scroll position and local query',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      final repo = FakeChatRepository()
        ..items = List.generate(
          30,
          (i) => ChatConversation(
            id: '$i',
            participant: ChatParticipant(id: '${i + 1}', name: 'Traveler $i'),
            preview: 'Test preview',
          ),
        );
      await show(tester, ChatsScreen(repository: repo));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Traveler');
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -240));
      await tester.pumpAndSettle();
      final before = tester
          .state<ScrollableState>(find.byType(Scrollable).last)
          .position
          .pixels;
      await tester.tap(find.byType(ChatListTile).hitTestable().first);
      await tester.pumpAndSettle();
      expect(find.byType(ConversationScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Traveler',
      );
      final after = tester
          .state<ScrollableState>(find.byType(Scrollable).last)
          .position
          .pixels;
      expect(after, closeTo(before, 1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final width in [320.0, 375.0, 393.0, 430.0]) {
    testWidgets(
      'anchored attachments and composer fit $width with keyboard and large text',
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewInsets);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        final repo = FakeChatRepository();
        await show(
          tester,
          ConversationScreen(
            repository: repo,
            conversation: conversation,
            currentUserId: 'self',
          ),
          width: width,
          scale: 1.6,
        );
        await tester.pumpAndSettle();
        final button = tester.getRect(find.byTooltip('Attachments'));
        expect(button.bottom, lessThanOrEqualTo(544));
        await tester.tap(find.byTooltip('Attachments'));
        await tester.pumpAndSettle();
        final menu = tester.getRect(find.byType(ChatAttachmentMenu));
        expect(menu.bottom, lessThan(button.top));
        expect(menu.left, greaterThanOrEqualTo(16));
        expect(menu.right, lessThanOrEqualTo(width - 16));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
