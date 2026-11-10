import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/shares/cubit/shares_cubit.dart';
import 'package:travibe/features/shares/data/post_share_actions.dart';
import 'package:travibe/features/shares/widgets/send_post_sheet.dart';
import 'fixtures.dart';
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
  late MemorySharesRepo sharesRepo;
  late SharesCubit shares;
  late SendPeopleRepo people;
  late TestActions actions;
  setUp(() {
    sharesRepo = MemorySharesRepo();
    shares = SharesCubit(repo: sharesRepo)
      ..acceptCounts({10: 2}, requestRevision: 0);
    people = SendPeopleRepo();
    actions = TestActions();
  });
  tearDown(() => shares.close());

  Future<void> show(
    WidgetTester tester, {
    bool hasLink = true,
    PostShareActions? shareActions,
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
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
                postText: 'Post text fixture',
                repo: people,
                actions: shareActions ?? (hasLink ? actions : null),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'renders rounded modal, search, horizontal people and actions without share writes',
    (tester) async {
      await show(tester);
      expect(find.text('Send Post'), findsOneWidget);
      expect(find.text('Traveller 2'), findsOneWidget);
      expect(find.text('Copy Link'), findsOneWidget);
      expect(find.text('More Options'), findsOneWidget);
      expect(find.text('Unshare from your profile'), findsNothing);
      expect(find.text('Share to your profile'), findsNothing);
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
      expect(sharesRepo.reads, isEmpty);
      expect(sharesRepo.creates, isEmpty);
      expect(sharesRepo.deletes, isEmpty);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(SendPostSheet), findsNothing);
      expect(shares.post(10).count, 2);
    },
  );

  testWidgets('debounces search and enforces existing query limits', (
    tester,
  ) async {
    await show(tester);
    await tester.enterText(find.byType(TextField), 'ab');
    await tester.pump(const Duration(milliseconds: 400));
    expect(people.calls, hasLength(1));
    expect(find.text('Search must contain 3–100 characters.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'alice');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'alice ');
    await tester.pump(const Duration(milliseconds: 100));
    expect(people.calls, hasLength(1));
    await tester.pumpAndSettle(const Duration(milliseconds: 350));
    expect(people.calls.last.query, 'alice');
    expect(people.calls, hasLength(2));
    await tester.enterText(find.byType(TextField), '');
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
    expect(sharesRepo.creates, isEmpty);
  });

  testWidgets(
    'Copy Link submits once while pending and does not mutate shares',
    (tester) async {
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
      expect(sharesRepo.creates, isEmpty);
      expect(shares.post(10).count, 2);
    },
  );

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
      expect(sharesRepo.creates, isEmpty);
      expect(sharesRepo.deletes, isEmpty);
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
    expect(sharesRepo.creates, isEmpty);
  });

  testWidgets(
    'missing URL disables Copy Link but enables native text without reposting',
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
      expect(
        find.text('Shares text only; no link to the original post.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Copy Link'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'More Options'))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('More Options'));
      await tester.pumpAndSettle();
      expect((call!.arguments as Map)['text'], 'Post text fixture');
      expect((call!.arguments as Map).containsKey('url'), isFalse);
      expect(find.text('Link copied'), findsNothing);
      expect(sharesRepo.reads, isEmpty);
      expect(sharesRepo.creates, isEmpty);
      expect(sharesRepo.deletes, isEmpty);
      expect(shares.post(10).count, 2);
    },
  );

  testWidgets(
    'action SVGs use the requested bundled assets without recoloring',
    (tester) async {
      await show(tester);
      final pictures = tester
          .widgetList<SvgPicture>(find.byType(SvgPicture))
          .toList();
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
      final icons = find.byType(SvgPicture);
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
          expect(sharesRepo.creates, isEmpty);
          expect(sharesRepo.deletes, isEmpty);
          expect(shares.post(10).count, 2);
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
    await tester.enterText(find.byType(TextField), 'alice');
    await tester.pumpAndSettle(const Duration(milliseconds: 350));
    await tester.ensureVisible(find.text('More Options'));
    expect(tester.takeException(), isNull);
  });
}
