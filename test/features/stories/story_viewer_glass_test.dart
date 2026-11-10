import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/home/widgets/home_user_avatar.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/screens/story_viewer_screen.dart';
import 'package:travibe/features/stories/widgets/story_glass.dart';
import 'package:travibe/features/stories/widgets/story_viewer_canvas.dart';
import 'package:travibe/features/stories/widgets/story_viewers_sheet.dart';
import 'fixtures.dart';
import 'story_owner_controls_test.dart' show OwnerRepo, viewersPage, viewerJson;
import 'story_viewer_test.dart' show viewerGroup, viewerDetail;
import 'story_publishing_test.dart' show pageJson;

const eye = 'assets/images/interactions/eye.svg';
Finder svg(String path) => find.byWidgetPredicate(
  (widget) =>
      widget is SvgPicture &&
      widget.bytesLoader is SvgAssetLoader &&
      (widget.bytesLoader as SvgAssetLoader).assetName == path,
);

void main() {
  final session = PreferencesManager();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await session.init();
    await session.saveToken('glass-test-session');
  });
  tearDown(() async => session.clear());

  Future<void> open(
    WidgetTester tester,
    OwnerRepo repo, {
    int userId = 7,
    FollowCubit? follow,
    BlockCubit? blocks,
    double scale = 1,
    EdgeInsets insets = EdgeInsets.zero,
  }) async {
    final photo = MemoryImage(photoBytes());
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: insets,
            viewPadding: insets,
            textScaler: TextScaler.linear(scale),
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
                    ],
                    initialAuthorId: 7,
                    currentUserId: userId,
                    repo: repo,
                    follow: follow,
                    blocks: blocks,
                    imageProvider: (_) => photo,
                  ),
                ),
              ),
              child: const Text('Open viewer'),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => precacheImage(photo, tester.element(find.text('Open viewer'))),
    );
    await tester.tap(find.text('Open viewer'));
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
  }

  testWidgets(
    'three bounded clipped glass surfaces keep the original canvas and controls',
    (tester) async {
      await open(tester, OwnerRepo());
      expect(find.byType(StoryGlass), findsNWidgets(3));
      final canvas = tester.getRect(find.byType(StoryViewerCanvas));
      for (final name in [
        'story-author-glass',
        'story-views-glass',
        'story-options-glass',
      ]) {
        final glass = find.byKey(ValueKey(name));
        expect(
          find.descendant(of: glass, matching: find.byType(ClipRRect)),
          findsWidgets,
        );
        final filter = find.descendant(
          of: glass,
          matching: find.byType(BackdropFilter),
        );
        expect(filter, findsOneWidget);
        final rect = tester.getRect(filter);
        expect(rect.width, lessThanOrEqualTo(canvas.width));
        expect(rect.height, lessThan(canvas.height / 2));
        expect(canvas.overlaps(rect), true);
        final decoration = tester.widget<DecoratedBox>(
          find.descendant(of: glass, matching: find.byType(DecoratedBox)).first,
        );
        expect(
          (decoration.decoration as BoxDecoration).color!.a,
          inExclusiveRange(0, 1),
        );
      }
      expect(
        tester.getRect(find.byKey(const ValueKey('story-author-glass'))).top,
        greaterThan(
          tester.getRect(find.byKey(const ValueKey('story-progress-0'))).bottom,
        ),
      );
      expect(find.byKey(const ValueKey('story-posting-time')), findsOneWidget);
      final image = tester.widget<Image>(
        find.byKey(const ValueKey('story-viewer-photo')),
      );
      expect(image.fit, BoxFit.cover);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'untinted native-size eye, real count, chevron and accessible vertical menu',
    (tester) async {
      await open(tester, OwnerRepo()..refreshedCount = 741);
      final picture = tester.widget<SvgPicture>(svg(eye));
      expect(picture.colorFilter, isNull);
      expect(picture.width, 24);
      expect(picture.height, 24);
      expect(find.text('741'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      final menu = tester.getSize(
        find.byKey(const ValueKey('story-owner-options')),
      );
      expect(menu.width, greaterThanOrEqualTo(48));
      expect(menu.height, greaterThanOrEqualTo(48));
      await tester.tap(find.byKey(const ValueKey('story-owner-options')));
      await tester.pumpAndSettle();
      expect(find.text('Delete story'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'views opens sheet with native eye and API-supported hearts/follow state only',
    (tester) async {
      final follow = FollowCubit();
      final blocks = BlockCubit(follow: follow);
      final repo = OwnerRepo()
        ..viewersHandler = (_) async => StoryViewersPage.fromJson(
          pageJson([
            viewerJson(8)
              ..['has_liked'] = true
              ..['is_following'] = false,
            viewerJson(9),
          ]),
        );
      await open(tester, repo, follow: follow, blocks: blocks);
      await tester.tap(find.byKey(const ValueKey('story-views')));
      await tester.pumpAndSettle();
      final sheet = find.byType(StoryViewersSheet);
      final sheetEye = find.descendant(of: sheet, matching: svg(eye));
      expect(sheetEye, findsOneWidget);
      expect(tester.widget<SvgPicture>(sheetEye).colorFilter, isNull);
      expect(find.text('12 Views'), findsOneWidget);
      expect(
        find.text('Only you can see who viewed your story.'),
        findsOneWidget,
      );
      expect(find.text('Follow'), findsOneWidget);
      expect(find.text('Following'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('story-viewer-liked-8')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('story-viewer-liked-9')), findsNothing);
      expect(
        tester
            .widget<SvgPicture>(svg('assets/images/interactions/heart.svg'))
            .colorFilter,
        isNull,
      );
      expect(
        find.descendant(of: sheet, matching: find.byIcon(Icons.more_vert)),
        findsNWidgets(2),
      );
      expect(
        find.descendant(of: sheet, matching: find.byType(HomeUserAvatar)),
        findsNWidgets(2),
      );
      await tester.pump(const Duration(seconds: 8));
      expect(find.text('12 Views'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await blocks.close();
      await follow.close();
    },
  );
  testWidgets(
    'loading then empty contains no fabricated names, hearts or follow controls',
    (tester) async {
      final pending = Completer<StoryViewersPage>();
      final repo = OwnerRepo()..viewersHandler = (_) => pending.future;
      await open(tester, repo);
      await tester.tap(find.byKey(const ValueKey('story-views')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final sheet = find.byType(StoryViewersSheet);
      expect(
        find.descendant(
          of: sheet,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.byType(HomeUserAvatar)),
        findsNothing,
      );
      expect(find.text('No viewers yet.'), findsNothing);
      pending.complete(StoryViewersPage.fromJson(viewersPage([])));
      await tester.pumpAndSettle();
      expect(find.text('No viewers yet.'), findsOneWidget);
      expect(svg('assets/images/interactions/heart.svg'), findsNothing);
      expect(find.text('Follow'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'error and retry retain empty private data until API confirmation',
    (tester) async {
      final repo = OwnerRepo()
        ..viewersHandler = (_) async =>
            throw ApiError(message: 'Unable to load viewers');
      await open(tester, repo);
      await tester.tap(find.byKey(const ValueKey('story-views')));
      await tester.pumpAndSettle();
      expect(find.text('Unable to load viewers'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(StoryViewersSheet),
          matching: find.byType(HomeUserAvatar),
        ),
        findsNothing,
      );
      repo.viewersHandler = (_) async =>
          StoryViewersPage.fromJson(viewersPage([]));
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(repo.pages, [1, 1]);
      expect(find.text('No viewers yet.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'viewer rows without supplied follow/block capabilities show no unsupported actions',
    (tester) async {
      await open(tester, OwnerRepo());
      await tester.tap(find.byKey(const ValueKey('story-views')));
      await tester.pumpAndSettle();
      final sheet = find.byType(StoryViewersSheet);
      expect(find.text('Viewer 8'), findsOneWidget);
      expect(
        find.descendant(of: sheet, matching: find.byIcon(Icons.more_vert)),
        findsNothing,
      );
      expect(find.text('Follow'), findsNothing);
      expect(find.text('Following'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final width in [320.0, 390.0, 430.0]) {
    testWidgets(
      'glass stays safe with long names, large counts and text on $width screen',
      (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final follow = FollowCubit();
        final blocks = BlockCubit(follow: follow);
        final repo = OwnerRepo()
          ..detailHandler = (id) async {
            final json = viewerDetail(id)..['views_count'] = 9007199254740991;
            (json['user'] as Map)['name'] =
                'A traveler with a very long display name that must fit';
            return StoryDetail.fromJson(json);
          }
          ..viewersHandler = (_) async => StoryViewersPage.fromJson(
            pageJson([viewerJson(8)..['has_liked'] = true]),
          );
        await open(
          tester,
          repo,
          follow: follow,
          blocks: blocks,
          scale: 2.5,
          insets: const EdgeInsets.only(top: 59, bottom: 34),
        );
        final author = tester.getRect(
          find.byKey(const ValueKey('story-author-glass')),
        );
        final menu = tester.getRect(
          find.byKey(const ValueKey('story-owner-options')),
        );
        expect(author.top, greaterThanOrEqualTo(59));
        expect(author.right, lessThanOrEqualTo(width - 16));
        expect(menu.bottom, lessThanOrEqualTo(844 - 34));
        expect(menu.right, lessThanOrEqualTo(width - 16));
        expect(find.text('9007199254740991'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('story-views')));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Viewer 8'),
          180,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text('Viewer 8'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await blocks.close();
        await follow.close();
      },
    );
  }
  testWidgets(
    'public story retains author glass but hides owner counter and menu',
    (tester) async {
      await open(tester, OwnerRepo(), userId: 9);
      expect(find.byType(StoryGlass), findsOneWidget);
      expect(find.byKey(const ValueKey('story-author-glass')), findsOneWidget);
      expect(find.byKey(const ValueKey('story-views')), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
