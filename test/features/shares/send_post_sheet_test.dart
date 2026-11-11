import 'dart:ui' show Tristate;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/shares/data/post_share_actions.dart';
import 'package:travibe/features/shares/data/share_post_messenger.dart';
import 'package:travibe/features/shares/widgets/send_post_sheet.dart';
import 'send_post_fixtures.dart';

class TestActions extends PostShareActions {
  TestActions()
    : super(verifiedPostUri: Uri.parse('https://example.invalid/test-post'));
  int copies = 0;
  int nativeCalls = 0;
  Rect? origin;
  Completer<void>? gate;
  bool fail = false;
  @override
  Future<void> copyLink() async {
    copies++;
    if (gate != null) await gate!.future;
    if (fail) throw PlatformException(code: 'failed');
  }

  @override
  Future<void> moreOptions(Rect origin) async {
    nativeCalls++;
    this.origin = origin;
    if (gate != null) await gate!.future;
    if (fail) throw PlatformException(code: 'unavailable');
  }
}

void main() {
  late SendPeopleRepo people;
  late RecordingChatRepository chat;
  late TestActions actions;
  setUp(() {
    people = SendPeopleRepo();
    chat = RecordingChatRepository();
    actions = TestActions();
  });

  Future<void> show(
    WidgetTester tester, {
    bool hasLink = true,
    PostShareActions? shareActions,
    PostModel? post,
    Size size = const Size(390, 844),
    bool appTheme = false,
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          // darkTheme needs ScreenUtil, so it is read inside the builder.
          theme: appTheme ? darkTheme : null,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => SendPostSheet.show(
                  context,
                  post: post ?? sharedPost(content: 'Post text fixture'),
                  repo: people,
                  messenger: SharePostMessenger(chat: chat),
                  actions: shareActions ?? (hasLink ? actions : null),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Finder user(String id) => find.byKey(ValueKey('send-post-user-$id'));
  Finder badge(String id) => find.byKey(ValueKey('send-post-selected-$id'));
  final send = find.byKey(const ValueKey('send-post-send'));
  final message = find.byKey(const ValueKey('send-post-message'));

  testWidgets('renders Figma layout: left title, search, people and actions', (
    tester,
  ) async {
    await show(tester);
    expect(find.text('Send Post'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('send-post-title'))).dx,
      lessThan(40),
    );
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Traveller 2'), findsOneWidget);
    expect(find.text('Copy Link'), findsOneWidget);
    expect(find.text('More Options'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Copy Link')).dx,
      lessThan(tester.getTopLeft(find.text('More Options')).dx),
    );
    expect(tester.getCenter(find.text('More Options')).dx, lessThan(195));
    expect(
      find.text('Shares text only; no link to the original post.'),
      findsNothing,
    );
    expect(message, findsNothing);
    expect(send, findsNothing);
    expect(
      tester.widget<ListView>(find.byType(ListView)).scrollDirection,
      Axis.horizontal,
    );
    final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(
      sheet.shape,
      const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(SendPostSheet), findsNothing);
    expect(chat.created, isEmpty);
  });

  testWidgets('non-public posts do not open the sheet', (tester) async {
    await show(tester, post: sharedPost(visibility: 'followers'));
    expect(find.byType(SendPostSheet), findsNothing);
    expect(find.text('Only public posts can be shared.'), findsOneWidget);
  });

  testWidgets(
    'tapping people toggles badges and swaps actions for the composer',
    (tester) async {
      await show(tester);
      await tester.tap(user('2'));
      await tester.pump();
      expect(badge('2'), findsOneWidget);
      final semantics = tester.getSemantics(user('2'));
      expect(semantics.label, 'Traveller 2');
      expect(semantics.flagsCollection.isSelected, Tristate.isTrue);
      expect(
        semantics.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      expect(find.text('Copy Link'), findsNothing);
      expect(find.text('More Options'), findsNothing);
      expect(find.text('Write Message'), findsOneWidget);
      expect(find.text('Send'), findsOneWidget);
      await tester.tap(user('3'));
      await tester.pump();
      expect(badge('2'), findsOneWidget);
      expect(badge('3'), findsOneWidget);
      await tester.tap(user('2'));
      await tester.tap(user('3'));
      await tester.pump();
      expect(badge('2'), findsNothing);
      expect(badge('3'), findsNothing);
      expect(find.text('Copy Link'), findsOneWidget);
      expect(send, findsNothing);
    },
  );

  testWidgets('Send shares to every selected person, closes and confirms', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(user('2'));
    await tester.tap(user('3'));
    await tester.pump();
    await tester.enterText(message, 'You should go!');
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(chat.created, ['2', '3']);
    expect(
      chat.sent.map((s) => s.text).toSet().single,
      'You should go!\n\nShared a post by Sara: “Post text fixture”',
    );
    expect(find.byType(SendPostSheet), findsNothing);
    expect(find.text('Sent to 2 people'), findsOneWidget);
  });

  testWidgets('single recipient snackbar names them', (tester) async {
    await show(tester);
    await tester.tap(user('2'));
    await tester.pump();
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(find.text('Sent to Traveller 2'), findsOneWidget);
  });

  testWidgets('partial failure stays open with per-person errors and retries', (
    tester,
  ) async {
    chat.failures['3'] = ApiError(message: 'Forbidden', statusCode: 403);
    await show(tester);
    await tester.tap(user('2'));
    await tester.tap(user('3'));
    await tester.pump();
    await tester.enterText(message, 'Note');
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(find.byType(SendPostSheet), findsOneWidget);
    expect(find.text('Sent to Traveller 2'), findsOneWidget);
    expect(
      find.text("Traveller 3: You can't message Traveller 3."),
      findsOneWidget,
    );
    expect(badge('2'), findsNothing);
    expect(badge('3'), findsOneWidget);
    expect(find.text('Note'), findsOneWidget);
    chat.failures.clear();
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(chat.created, ['2', '3', '3']);
    expect(find.byType(SendPostSheet), findsNothing);
  });

  testWidgets('Send is disabled while sending and people are locked', (
    tester,
  ) async {
    chat.gate = Completer<void>();
    await show(tester);
    await tester.tap(user('2'));
    await tester.pump();
    await tester.tap(send);
    await tester.pump();
    expect(find.text('Sending…'), findsOneWidget);
    await tester.tap(send);
    await tester.tap(user('3'));
    await tester.pump();
    expect(badge('3'), findsNothing);
    chat.gate!.complete();
    await tester.pumpAndSettle();
    expect(chat.created, ['2']);
  });

  testWidgets('search filters people and keeps selections visible', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(user('2'));
    await tester.pump();
    people.result = peoplePage([person('9')]);
    await tester.enterText(
      find.byKey(const ValueKey('send-post-search')),
      'tra',
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 350));
    expect(people.calls.last.query, 'tra');
    expect(find.text('Traveller 9'), findsOneWidget);
    expect(find.text('Traveller 3'), findsNothing);
    expect(badge('2'), findsOneWidget);
  });

  testWidgets('debounces search and enforces existing query limits', (
    tester,
  ) async {
    await show(tester);
    final search = find.byKey(const ValueKey('send-post-search'));
    await tester.enterText(search, 'ab');
    await tester.pump(const Duration(milliseconds: 400));
    expect(people.calls, hasLength(1));
    expect(find.text('Search must contain 3–100 characters.'), findsOneWidget);
    await tester.enterText(search, 'alice');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(search, 'alice ');
    await tester.pump(const Duration(milliseconds: 100));
    expect(people.calls, hasLength(1));
    await tester.pumpAndSettle(const Duration(milliseconds: 350));
    expect(people.calls.last.query, 'alice');
    expect(people.calls, hasLength(2));
    await tester.enterText(search, '');
    await tester.pumpAndSettle(const Duration(milliseconds: 350));
    expect(people.calls.last.query, '');
  });

  testWidgets('people errors retry and empty results render', (tester) async {
    people.error = ApiError(message: 'People unavailable');
    await show(tester);
    expect(find.text('People unavailable'), findsOneWidget);
    people.error = null;
    people.result = peoplePage([]);
    await tester.tap(find.text('Retry people'));
    await tester.pumpAndSettle();
    expect(find.text('No suggested people yet.'), findsOneWidget);
  });

  testWidgets('Copy Link submits once while pending', (tester) async {
    await show(tester);
    actions.gate = Completer<void>();
    await tester.tap(find.text('Copy Link'));
    await tester.pump();
    await tester.tap(find.text('Copy Link'));
    await tester.tap(find.text('More Options'));
    expect(actions.copies, 1);
    expect(actions.nativeCalls, 0);
    actions.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Link copied'), findsOneWidget);
  });

  testWidgets(
    'native sharing is anchored, prevents duplicates, and dismissal does not claim delivery',
    (tester) async {
      await show(tester);
      actions.gate = Completer<void>();
      await tester.tap(find.text('More Options'));
      await tester.pump();
      await tester.tap(find.text('More Options'));
      expect(actions.nativeCalls, 1);
      expect(actions.origin!.width, greaterThan(0));
      expect(actions.origin!.height, greaterThan(0));
      actions.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Link copied'), findsNothing);
      expect(find.byType(SendPostSheet), findsOneWidget);
      expect(chat.created, isEmpty);
    },
  );

  testWidgets('external errors stay local and allow retry', (tester) async {
    actions.fail = true;
    await show(tester);
    await tester.tap(find.text('Copy Link'));
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to copy the link. Please try again.'),
      findsOneWidget,
    );
    await tester.tap(find.text('More Options'));
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to open sharing options. Please try again.'),
      findsOneWidget,
    );
    actions.fail = false;
    await tester.tap(find.text('Copy Link'));
    await tester.pumpAndSettle();
    expect(find.text('Link copied'), findsOneWidget);
  });

  testWidgets(
    'missing URL: Copy Link explains, More Options shares post text',
    (tester) async {
      MethodCall? call;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(PostShareActions.channel, (
        value,
      ) async {
        call = value;
        return null;
      });
      addTearDown(
        () =>
            messenger.setMockMethodCallHandler(PostShareActions.channel, null),
      );
      await show(tester, hasLink: false);
      await tester.tap(find.text('Copy Link'));
      await tester.pump();
      expect(find.text("Post links aren't available yet."), findsOneWidget);
      expect(find.text('Link copied'), findsNothing);
      await tester.tap(find.text('More Options'));
      await tester.pumpAndSettle();
      expect((call!.arguments as Map)['text'], 'Post text fixture');
      expect((call!.arguments as Map).containsKey('url'), isFalse);
    },
  );

  testWidgets('posts without text share the fallback text', (tester) async {
    MethodCall? call;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(PostShareActions.channel, (value) async {
      call = value;
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(PostShareActions.channel, null),
    );
    await show(tester, hasLink: false, post: sharedPost(content: null));
    await tester.tap(find.text('More Options'));
    await tester.pumpAndSettle();
    expect((call!.arguments as Map)['text'], 'A post on Travibe.');
  });

  testWidgets(
    'action SVGs use the requested bundled assets without recoloring',
    (tester) async {
      await show(tester);
      final actionIcons = find.descendant(
        of: find.byType(TextButton),
        matching: find.byType(SvgPicture),
      );
      final pictures = tester.widgetList<SvgPicture>(actionIcons).toList();
      expect(pictures, hasLength(2));
      expect(
        pictures.map(
          (picture) => (picture.bytesLoader as SvgAssetLoader).assetName,
        ),
        [
          'assets/images/interactions/link.svg',
          'assets/images/interactions/share.svg',
        ],
      );
      for (final picture in pictures) {
        expect(picture.colorFilter, isNull);
        final asset = (picture.bytesLoader as SvgAssetLoader).assetName;
        expect(
          await tester.runAsync(() => rootBundle.loadString(asset)),
          contains('<svg'),
        );
      }
      final icons = actionIcons;
      expect(tester.getSize(icons.at(0)), const Size(46, 46));
      expect(tester.getSize(icons.at(1)), const Size(32, 32));
      expect(tester.takeException(), isNull);
    },
  );

  for (final failure in <Object>[
    PlatformException(
      code: 'unavailable',
      message: 'Native presentation failed',
      details: 'Test native details',
    ),
    MissingPluginException('No handler for travibe/post_sharing'),
  ]) {
    testWidgets(
      '${failure.runtimeType} is logged with stack, keeps friendly feedback and allows retry',
      (tester) async {
        final logs = <String>[];
        final originalPrint = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) =>
            logs.add(message ?? '');
        try {
          final messenger =
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
          messenger.setMockMethodCallHandler(PostShareActions.channel, (
            _,
          ) async {
            throw failure;
          });
          addTearDown(
            () => messenger.setMockMethodCallHandler(
              PostShareActions.channel,
              null,
            ),
          );
          await show(tester, hasLink: false);
          await tester.tap(find.text('More Options'));
          await tester.pumpAndSettle();
          expect(
            find.text('Unable to open sharing options. Please try again.'),
            findsOneWidget,
          );
          expect(logs.join('\n'), contains(failure.runtimeType.toString()));
          expect(logs.join('\n'), contains('travibe/post_sharing'));
          expect(logs.join('\n'), contains('#0'));
          if (failure is PlatformException) {
            expect(logs.join('\n'), contains('Test native details'));
          }
          messenger.setMockMethodCallHandler(
            PostShareActions.channel,
            (_) async => null,
          );
          await tester.tap(find.text('More Options'));
          await tester.pumpAndSettle();
          expect(
            find.text('Unable to open sharing options. Please try again.'),
            findsNothing,
          );
        } finally {
          debugPrint = originalPrint;
        }
      },
    );
  }

  testWidgets('keyboard, large text and small screens stay scrollable', (
    tester,
  ) async {
    await show(tester, size: const Size(320, 480), scale: 1.5);
    tester.view.viewInsets = const FakeViewPadding(bottom: 180);
    addTearDown(tester.view.resetViewInsets);
    await tester.tap(user('2'));
    await tester.pump();
    await tester.enterText(message, 'A long note ' * 20);
    await tester.pumpAndSettle();
    await tester.ensureVisible(send);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search uses the shared search-normal SVG like Chats', (
    tester,
  ) async {
    await show(tester, appTheme: true);
    final icon = find.byKey(const ValueKey('send-post-search-icon'));
    final picture = tester.widget<SvgPicture>(icon);
    expect(
      (picture.bytesLoader as SvgAssetLoader).assetName,
      'assets/images/interactions/search-normal.svg',
    );
    expect(picture.colorFilter, isNull);
    expect(tester.getSize(icon), const Size(20, 20));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('send-post-search')),
        matching: icon,
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'Write Message is transparent and multi-line under the app theme',
    (tester) async {
      await show(tester, appTheme: true);
      await tester.tap(user('2'));
      await tester.pump();
      final field = tester.widget<TextField>(message);
      final decoration = field.decoration!;
      expect(decoration.filled, isFalse);
      for (final border in [
        decoration.border,
        decoration.enabledBorder,
        decoration.focusedBorder,
        decoration.disabledBorder,
      ]) {
        expect(border, InputBorder.none);
      }
      expect(decoration.hintStyle!.color, DarkColors.greyColor);
      expect(decoration.hintStyle!.fontSize, 14);
      expect(field.style!.color, DarkColors.whiteColor);
      expect(field.style!.fontSize, 14);
      expect(field.cursorColor, DarkColors.whiteColor);
      expect(field.minLines, 1);
      expect(field.maxLines, 4);
      // The rendered decorator must not pick up the theme's white fill.
      final rendered = tester.widget<InputDecorator>(
        find.descendant(of: message, matching: find.byType(InputDecorator)),
      );
      expect(rendered.decoration.filled, isFalse);
      final oneLine = tester.getSize(message).height;
      await tester.enterText(message, 'one\ntwo\nthree\nfour\nfive\nsix');
      await tester.pump();
      final grown = tester.getSize(message).height;
      expect(grown, greaterThan(oneLine * 2));
      expect(grown, lessThan(oneLine * 4.5));
      expect(tester.takeException(), isNull);
    },
  );
}
