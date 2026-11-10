import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/block/data/block_repo.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/stories/screens/story_viewer_screen.dart';
import 'package:travibe/features/stories/widgets/story_reply_composer.dart';
import 'package:travibe/features/stories/widgets/story_viewer_canvas.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'fixtures.dart';
import 'story_owner_controls_test.dart' show OwnerRepo;
import 'story_likes_test.dart' show reaction;
import 'story_viewer_test.dart' show viewerGroup, viewerDetail;

class StoryBlocks extends BlockRepo {
  int checks = 0, changes = 0;
  bool fail = false;
  Completer<BlockStatus>? pendingStatus;
  @override
  Future<BlockStatus> status(String id) async {
    checks++;
    return pendingStatus == null
        ? BlockStatus(userId: id, isBlocked: false)
        : pendingStatus!.future;
  }

  @override
  Future<PublicUserModel> setBlocked(String id, bool blocked) async {
    changes++;
    if (fail) throw ApiError(message: 'Block failed');
    return PublicUserModel(
      id: id,
      name: 'Traveler',
      isFollowing: false,
      isBlocked: blocked,
      followersCount: 0,
      followingCount: 0,
    );
  }
}

Finder customSvg(String name) => find.byWidgetPredicate(
  (widget) =>
      widget is SvgPicture &&
      widget.bytesLoader is SvgAssetLoader &&
      (widget.bytesLoader as SvgAssetLoader).assetName ==
          'assets/images/interactions/$name',
);

void main() {
  final session = PreferencesManager();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await session.init();
    await session.saveToken('other-story-test');
  });
  tearDown(() async => session.clear());

  Future<void> open(
    WidgetTester tester, {
    bool mine = false,
    bool nextAuthor = false,
    BlockCubit? blocks,
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final photo = MemoryImage(photoBytes());
    final repo = OwnerRepo()
      ..detailHandler = (id) async => id == 3
          ? StoryDetail.fromJson(
              viewerDetail(3, author: 9)..['is_mine'] = false,
            )
          : reaction(id, mine: mine);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQueryData(
            size: Size(width, 844),
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            viewPadding: const EdgeInsets.only(top: 59, bottom: 34),
            textScaler: TextScaler.linear(scale),
            viewInsets: MediaQuery.viewInsetsOf(context),
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StoryViewerScreen(
                    groups: [
                      viewerGroup(7, [1, 2]),
                      if (nextAuthor) viewerGroup(9, [3]),
                    ],
                    initialAuthorId: 7,
                    currentUserId: mine ? 7 : 8,
                    repo: repo,
                    blocks: blocks,
                    imageProvider: (_) => photo,
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => precacheImage(photo, tester.element(find.text('Open'))),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
  }

  Finder field() => find.byKey(const ValueKey('story-reply-field'));
  Future<void> options(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('story-other-options')));
    await tester.pumpAndSettle();
  }

  double progress(WidgetTester tester) => tester
      .widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('story-progress-0')),
      )
      .value!;

  testWidgets(
    'other-user row has composer and independent heart/options; owner controls unchanged',
    (tester) async {
      await open(tester);
      expect(field(), findsOneWidget);
      final emoji = customSvg('happyemoji.svg');
      expect(emoji, findsOneWidget);
      expect(tester.getSize(emoji), const Size(20, 20));
      expect(tester.widget<SvgPicture>(emoji).colorFilter, isNull);
      expect(find.byIcon(Icons.sentiment_satisfied_alt_outlined), findsNothing);
      expect(find.byKey(const ValueKey('story-like')), findsOneWidget);
      expect(find.byKey(const ValueKey('story-other-options')), findsOneWidget);
      expect(find.byKey(const ValueKey('story-owner-options')), findsNothing);
    },
  );
  testWidgets(
    'owner has views/delete controls and no composer or other options',
    (tester) async {
      await open(tester, mine: true);
      expect(field(), findsNothing);
      expect(find.byKey(const ValueKey('story-like')), findsNothing);
      expect(find.byKey(const ValueKey('story-owner-options')), findsOneWidget);
      expect(find.byKey(const ValueKey('story-views')), findsOneWidget);
    },
  );
  testWidgets(
    'typing pauses progress, Done resumes and preserves the current draft without sending',
    (tester) async {
      await open(tester);
      await tester.tap(field());
      await tester.enterText(field(), 'Draft only');
      await tester.pump();
      final paused = progress(tester);
      await tester.pump(const Duration(seconds: 7));
      expect(progress(tester), paused);
      expect(find.text('Replies are not available yet.'), findsOneWidget);
      expect(find.byIcon(Icons.send), findsNothing);
      final svgSend = find.ancestor(
        of: customSvg('send.svg'),
        matching: find.byType(IconButton),
      );
      expect(customSvg('send.svg'), findsOneWidget);
      expect(tester.widget<IconButton>(svgSend).onPressed, isNull);
      expect(
        tester.widget<IconButton>(svgSend).tooltip,
        'Send message (coming soon)',
      );
      expect(tester.widget<TextField>(field()).controller!.text, 'Draft only');
      expect(progress(tester), paused);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(tester.widget<TextField>(field()).controller!.text, 'Draft only');
      await tester.pump(const Duration(milliseconds: 200));
      expect(progress(tester), greaterThan(paused));
    },
  );
  testWidgets(
    'native keyboard dismissal resumes playback and preserves draft; story change clears it',
    (tester) async {
      await open(tester);
      await tester.tap(field());
      await tester.enterText(field(), 'First story');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      final paused = progress(tester);
      await tester.pump(const Duration(seconds: 7));
      expect(progress(tester), paused);
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pump();
      expect(tester.widget<TextField>(field()).focusNode!.hasFocus, isFalse);
      expect(tester.widget<TextField>(field()).controller!.text, 'First story');
      await tester.pump(const Duration(milliseconds: 200));
      expect(progress(tester), greaterThan(paused));
      final taps = find.byKey(const ValueKey('story-viewer-taps'));
      await tester.tapAt(tester.getTopRight(taps) + const Offset(-30, 240));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field()).controller!.text, isEmpty);
      expect(
        tester
            .widget<StoryReplyComposer>(find.byType(StoryReplyComposer))
            .storyId,
        2,
      );
    },
  );
  testWidgets(
    'options pause and outside dismissal resumes; Report is disabled and never blocks',
    (tester) async {
      final repo = StoryBlocks();
      final follow = FollowCubit();
      final blocks = BlockCubit(follow: follow, repo: repo);
      await open(tester, blocks: blocks);
      await options(tester);
      final report = tester.widget<ListTile>(
        find.byKey(const ValueKey('story-report')),
      );
      for (final name in ['flag.svg', 'user-remove.svg']) {
        final icon = customSvg(name);
        expect(icon, findsOneWidget);
        expect(tester.getSize(icon), const Size(24, 24));
        expect(tester.widget<SvgPicture>(icon).colorFilter, isNull);
      }
      expect(find.byIcon(Icons.flag_outlined), findsNothing);
      expect(find.byIcon(Icons.person_off_outlined), findsNothing);
      expect(report.enabled, false);
      expect(report.onTap, isNull);
      expect(find.text('Reporting is not available yet.'), findsOneWidget);
      final paused = progress(tester);
      await tester.pump(const Duration(seconds: 7));
      expect(progress(tester), paused);
      expect(repo.changes, 0);
      expect(repo.checks, 0);
      await tester.tapAt(const Offset(10, 100));
      await tester.pumpAndSettle();
      expect(find.text('Report'), findsNothing);
      await tester.pump(const Duration(milliseconds: 200));
      expect(progress(tester), greaterThan(paused));
      await tester.pumpWidget(const SizedBox.shrink());
      await blocks.close();
      await follow.close();
    },
  );
  for (final fail in [false, true]) {
    testWidgets(
      'existing BlockCubit confirmation ${fail ? 'failure retains story' : 'success removes blocked stories'}',
      (tester) async {
        final repo = StoryBlocks()..fail = fail;
        final follow = FollowCubit();
        final blocks = BlockCubit(follow: follow, repo: repo);
        await open(tester, blocks: blocks);
        await options(tester);
        await tester.tap(find.byKey(const ValueKey('story-block-user')));
        await tester.pumpAndSettle();
        expect(find.text('Block user?'), findsOneWidget);
        expect(repo.changes, 0);
        await tester.tap(find.widgetWithText(TextButton, 'Block'));
        await tester.pumpAndSettle();
        expect(repo.checks, 1);
        expect(repo.changes, 1);
        if (fail) {
          expect(find.text('Block failed'), findsOneWidget);
          expect(find.byType(StoryViewerScreen), findsOneWidget);
          expect(blocks.state.isBlocked('7'), false);
        } else {
          expect(blocks.state.isBlocked('7'), true);
          expect(find.byType(StoryViewerScreen), findsNothing);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await blocks.close();
        await follow.close();
      },
    );
  }
  testWidgets(
    'cancel block never mutates; duplicate status taps are disabled',
    (tester) async {
      final pending = Completer<BlockStatus>();
      final repo = StoryBlocks()..pendingStatus = pending;
      final follow = FollowCubit();
      final blocks = BlockCubit(follow: follow, repo: repo);
      await open(tester, blocks: blocks);
      await options(tester);
      await tester.tap(find.byKey(const ValueKey('story-block-user')));
      await tester.pump();
      expect(
        tester
            .widget<ListTile>(find.byKey(const ValueKey('story-block-user')))
            .onTap,
        isNull,
      );
      expect(repo.checks, 1);
      pending.complete(BlockStatus(userId: '7', isBlocked: false));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(repo.changes, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await blocks.close();
      await follow.close();
    },
  );
  testWidgets('session change clears focused reply and closes viewer', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(field());
    await tester.enterText(field(), 'Private draft');
    await session.saveToken('next-account');
    await tester.pumpAndSettle();
    expect(find.byType(StoryViewerScreen), findsNothing);
    expect(find.text('Private draft'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('disposal while focused releases controller and focus safely', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(field());
    await tester.enterText(field(), 'Draft');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'keyboard inset does not resize canvas; native dismissal releases focus',
    (tester) async {
      await open(tester);
      final original = tester.getRect(find.byType(StoryViewerCanvas));
      await tester.tap(field());
      await tester.enterText(field(), 'Draft');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      expect(tester.getRect(find.byType(StoryViewerCanvas)), original);
      tester.view.resetViewInsets();
      await tester.pump();
      expect(tester.widget<TextField>(field()).focusNode!.hasFocus, false);
      expect(tester.widget<TextField>(field()).controller!.text, 'Draft');
    },
  );
  testWidgets(
    'blocking current author dismisses options and advances to next author',
    (tester) async {
      final repo = StoryBlocks();
      final follow = FollowCubit();
      final blocks = BlockCubit(follow: follow, repo: repo);
      await open(tester, blocks: blocks, nextAuthor: true);
      await options(tester);
      await tester.tap(find.byKey(const ValueKey('story-block-user')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Block'));
      await tester.pumpAndSettle();
      expect(find.text('Report'), findsNothing);
      expect(find.byType(StoryViewerScreen), findsOneWidget);
      expect(
        tester
            .widget<StoryReplyComposer>(find.byType(StoryReplyComposer))
            .storyId,
        3,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await blocks.close();
      await follow.close();
    },
  );
  testWidgets(
    'account change during block check cannot open confirmation or mutate',
    (tester) async {
      final pending = Completer<BlockStatus>();
      final repo = StoryBlocks()..pendingStatus = pending;
      final follow = FollowCubit();
      final blocks = BlockCubit(follow: follow, repo: repo);
      await open(tester, blocks: blocks);
      await options(tester);
      await tester.tap(find.byKey(const ValueKey('story-block-user')));
      await tester.pump();
      await session.saveToken('different-account');
      await tester.pumpAndSettle();
      pending.complete(BlockStatus(userId: '7', isBlocked: false));
      await tester.pumpAndSettle();
      expect(find.text('Block user?'), findsNothing);
      expect(repo.changes, 0);
      expect(find.byType(StoryViewerScreen), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await blocks.close();
      await follow.close();
    },
  );
  for (final width in [320.0, 390.0]) {
    testWidgets('bottom row fits $width with large text and safe insets', (
      tester,
    ) async {
      await open(tester, width: width, scale: 2.5);
      expect(tester.takeException(), isNull);
      final row = tester.getRect(
        find.byKey(const ValueKey('story-other-controls')),
      );
      expect(row.left, greaterThanOrEqualTo(16));
      expect(row.right, lessThanOrEqualTo(width - 16));
      expect(row.bottom, lessThanOrEqualTo(844 - 34));
      await tester.tap(field());
      await tester.enterText(
        field(),
        'Long local draft that stays inside its field',
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
