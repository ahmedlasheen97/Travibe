import 'package:travibe/core/widgets/home_post_caption.dart';
import 'package:travibe/features/stories/widgets/story_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/post_card.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/features/home/data/posts_page_model.dart';
import 'package:travibe/features/home/screens/home_screen.dart';
import 'package:travibe/features/home/widgets/home_stories.dart';
import 'package:travibe/features/home/widgets/home_tabs.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';
import 'package:travibe/features/stories/widgets/post_story_sheet.dart';
import 'package:travibe/features/search/screens/search_screen.dart';
import 'package:travibe/features/search/data/search_repo.dart';
import 'package:travibe/core/widgets/action_icon_button.dart';
import '../../helpers/cursor_fixtures.dart';
import 'home_experience_fixtures.dart' as fixture;

Map<String, dynamic> storyGroup(int id) => {
  'user': {
    'id': id,
    'name': id == 2
        ? 'A very long traveler name that must truncate'
        : 'Traveler $id',
    'avatar_url': null,
  },
  'has_unseen': id.isEven,
  'stories': [
    {
      'id': id * 10,
      'has_seen': !id.isEven,
      'views_count': 0,
      'expires_at': '2030-11-03T00:00:00Z',
    },
  ],
};

class ResponsiveStories extends StoriesRepo {
  int reads = 0;
  @override
  Future<StoriesPage> getStories({int page = 1}) async {
    reads++;
    return StoriesPage.fromJson({
      'data': List.generate(12, (i) => storyGroup(i + 2)),
      'meta': {'current_page': 1, 'last_page': 1, 'per_page': 15, 'total': 12},
      'links': {'first': null, 'last': null, 'next': null, 'prev': null},
    });
  }
}

class ResponsiveSearch extends SearchRepo {
  @override
  Future<String> getCurrentUserId() async => '1';
}

class ResponsivePosts extends PostsRepo {
  final reads = <({FeedType feed, String? cursor})>[];
  @override
  Future<PostsPageModel> getPosts({
    FeedType feed = FeedType.explore,
    String? cursor,
    int perPage = 15,
  }) async {
    reads.add((feed: feed, cursor: cursor));
    final base = feed == FeedType.explore ? 0 : 100;
    return PostsPageModel.fromCursorJson(
      cursorEnvelope(
        next: cursor == null ? 'next-$base' : null,
        data: List.generate(
          cursor == null ? 8 : 2,
          (i) => {
            'id': base + (cursor == null ? i + 1 : 20 + i),
            'user_id': 7,
            'user': {
              'id': 7,
              'name': 'Traveler with a long display name',
              'is_following': false,
            },
            'content': 'An actual backend-shaped post with dynamic text. ' * 6,
            'visibility': 'public',
            'likes_count': 123456,
            'comments_count': 4567,
            'media': [
              {'url': 'assets/images/onboarding/on1.png'},
            ],
          },
        ),
      ),
    );
  }
}

void main() {
  late ResponsiveStories stories;
  late ResponsivePosts posts;
  late fixture.AccountRepo account;
  late FollowCubit follow;
  late BlockCubit block;
  setUpAll(() async {
    final fonts = FontLoader('Plus Jakarta Sans')
      ..addFont(rootBundle.load('assets/fonts/PlusJakartaSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/PlusJakartaSans-SemiBold.ttf'))
      ..addFont(rootBundle.load('assets/fonts/PlusJakartaSans-Bold.ttf'));
    await fonts.load();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('responsive-test-session');
    stories = ResponsiveStories();
    posts = ResponsivePosts();
    account = fixture.AccountRepo()..followingCount = 2;
    follow = FollowCubit(repo: fixture.PeopleRepo(account));
    block = BlockCubit(follow: follow);
  });
  tearDown(() async {
    await block.close();
    await follow.close();
    await PreferencesManager().clear();
  });
  Future<void> show(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: follow),
                BlocProvider.value(value: block),
              ],
              child: HomeScreen(
                postsRepo: posts,
                accountRepo: account,
                storiesRepo: stories,
                searchRepo: ResponsiveSearch(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ScrollPosition storyPosition(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(HomeStories),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;
  ScrollController vertical(WidgetTester tester) => tester
      .widget<CustomScrollView>(find.byType(CustomScrollView))
      .controller!;

  testWidgets(
    'reference avatar is 64px inside a circular 72px viewed/unviewed ring with safe names',
    (tester) async {
      await show(tester);
      expect(AppSizes.w64, 64);
      expect(AppSizes.h64, 64);
      for (final id in [2, 3]) {
        final avatar = find.byKey(ValueKey('story-avatar-$id'));
        final ring = find.byKey(ValueKey('story-ring-$id'));
        expect(tester.getSize(avatar), const Size.square(64));
        expect(tester.getSize(ring), const Size.square(72));
        final paint =
            tester
                    .widget<CustomPaint>(
                      find.descendant(
                        of: find.byKey(ValueKey('story-segments-$id')),
                        matching: find.byType(CustomPaint),
                      ),
                    )
                    .foregroundPainter!
                as StoryRingPainter;
        expect(
          paint.colors.single,
          id.isEven ? DarkColors.primaryColor : Colors.white24,
        );
      }
      final name = tester.widget<Text>(
        find.text('A very long traveler name that must truncate'),
      );
      expect(name.maxLines, 1);
      expect(name.overflow, TextOverflow.ellipsis);
      expect(
        tester.getSize(find.byKey(const ValueKey('story-avatar-you'))),
        const Size.square(64),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'tab switches preserve the story element, horizontal offset, states, and both feed caches',
    (tester) async {
      await show(tester);
      final element = tester.element(find.byType(HomeStories));
      final position = storyPosition(tester);
      await tester.drag(
        find.byKey(const PageStorageKey('home-stories-scroll')),
        const Offset(-220, 0),
      );
      await tester.pumpAndSettle();
      final offset = position.pixels;
      expect(offset, greaterThan(0));
      for (final label in ['Following', 'For You', 'Following', 'For You']) {
        await tester.tap(
          find.descendant(
            of: find.byType(HomeTabs),
            matching: find.text(label),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.element(find.byType(HomeStories)), same(element));
        expect(storyPosition(tester), same(position));
        expect(storyPosition(tester).pixels, closeTo(offset, .01));
        expect(stories.reads, 1);
        expect(
          tester.widget<HomeStories>(find.byType(HomeStories)).loading,
          false,
        );
      }
      expect(
        posts.reads.where((r) => r.feed == FeedType.explore),
        hasLength(1),
      );
      expect(
        posts.reads.where((r) => r.feed == FeedType.following),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'feed offsets and cursor continuation are retained when returning to a cached tab',
    (tester) async {
      await show(tester);
      vertical(tester).jumpTo(80);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Following').first);
      await tester.pumpAndSettle();
      expect(vertical(tester).offset, 0);
      vertical(tester).jumpTo(120);
      await tester.pumpAndSettle();
      await tester.tap(find.text('For You').first);
      await tester.pumpAndSettle();
      expect(vertical(tester).offset, 80);
      vertical(tester).jumpTo(vertical(tester).position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(posts.reads.last.cursor, 'next-0');
      expect(
        posts.reads.where(
          (r) => r.feed == FeedType.explore && r.cursor == null,
        ),
        hasLength(1),
      );
      expect(stories.reads, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Add Story still opens the existing creation sheet and Search opens its existing route',
    (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('add-story-photo')));
      await tester.pumpAndSettle();
      expect(find.byType(PostStorySheet), findsOneWidget);
      Navigator.of(tester.element(find.byType(PostStorySheet))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-search')));
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final size in [
    const Size(320, 694),
    const Size(375, 812),
    const Size(393, 852),
    const Size(430, 932),
    const Size(844, 390),
    const Size(1024, 768),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Home remains responsive at $size with text scale $scale', (
        tester,
      ) async {
        await show(tester, size: size, textScale: scale);
        final first = find.descendant(
          of: find.byType(HomeTabs),
          matching: find.text('For You'),
        );
        final second = find.descendant(
          of: find.byType(HomeTabs),
          matching: find.text('Following'),
        );
        for (final label in [first, second]) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(of: label, matching: find.byType(RichText)),
          );
          // A centered group must reserve Search's full target on both sides.
          // At enlarged text sizes, labels may ellipsize while retaining their
          // complete semantics and system font scaling.
          if (scale == 1) expect(paragraph.didExceedMaxLines, false);
        }
        final group = tester.getRect(
          find.byKey(const ValueKey('home-feed-tab-group')),
        );
        expect(group.center.dx, closeTo(size.width / 2, .01));
        final searchTarget = tester.getRect(
          find.byKey(const ValueKey('home-search')),
        );
        expect(group.right, lessThan(searchTarget.left));
        final tabsRect = tester.getRect(find.byType(HomeTabs));
        expect(
          searchTarget.right,
          closeTo(tabsRect.right - AppSizes.adaptiveWidth(20), .01),
        );
        final icon = find.byKey(const ValueKey('home-search-icon'));
        expect(
          tester.getCenter(first).dy,
          closeTo(tester.getCenter(second).dy, .1),
        );
        expect(
          tester.getCenter(first).dy,
          closeTo(tester.getCenter(icon).dy, .1),
        );
        expect(
          tester.getRect(icon).left,
          greaterThan(tester.getRect(second).right),
        );
        final avatar = tester.getSize(
          find.byKey(const ValueKey('story-avatar-you')),
        );
        expect(avatar.width, avatar.height);
        expect(avatar.width, inInclusiveRange(56, 72));
        final ring = tester.getSize(
          find.byKey(const ValueKey('story-ring-you')),
        );
        expect(ring.width, ring.height);
        expect(tester.takeException(), isNull);
        // Exercise post typography/actions after scrolling the dynamic header away.
        await tester.ensureVisible(find.byType(PostCard).first);
        await tester.pumpAndSettle();
        expect(
          tester.widget<PostCard>(find.byType(PostCard).first).responsive,
          true,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
  testWidgets(
    'responsive post actions preserve callbacks with large counts and text',
    (tester) async {
      await show(tester, size: const Size(320, 694), textScale: 2);
      var likes = 0, comments = 0, shares = 0, saves = 0;
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          minTextAdapt: true,
          splitScreenMode: true,
          builder: (_, _) => MaterialApp(
            theme: darkTheme,
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: PostCard(
                    responsive: true,
                    name: 'A long traveler name',
                    avatar: null,
                    time: 'Now',
                    text: 'A dynamic caption',
                    location:
                        'A very long location that must wrap without horizontal overflow',
                    likes: '123.4K',
                    comments: '456.7K',
                    onLikeTap: () => likes++,
                    onCommentsTap: () => comments++,
                    onShareTap: () => shares++,
                    onSaveTap: () => saves++,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('post-like')));
      final comment = find.byWidgetPredicate(
        (w) =>
            w is ActionIconButton &&
            w.iconPath == 'assets/images/interactions/message.svg',
      );
      await tester.tap(comment);
      await tester.tap(find.byKey(const ValueKey('post-share')));
      await tester.tap(find.byKey(const ValueKey('post-save')));
      expect([likes, comments, shares, saves], [1, 1, 1, 1]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'populated feed can scroll through its auxiliary sections with large text',
    (tester) async {
      await show(tester, size: const Size(320, 694), textScale: 2);
      for (var offset = 300.0; offset < 6000; offset += 300) {
        final max = vertical(tester).position.maxScrollExtent;
        vertical(tester).jumpTo(offset.clamp(0, max));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (offset >= max &&
            tester.widgetList<PostCard>(find.byType(PostCard)).isNotEmpty) {
          break;
        }
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'new AppSizes getters recalculate when initialized metrics change',
    (tester) async {
      await show(tester);
      expect(AppSizes.w64, 64);
      await tester.pumpWidget(const SizedBox());
      ScreenUtil.configure(
        data: const MediaQueryData(size: Size(430, 932)),
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
      );
      expect(AppSizes.w64, closeTo(64 * 430 / 390, .001));
      expect(AppSizes.h64, closeTo(64 * 932 / 844, .001));
    },
  );
  testWidgets(
    'inline caption expansion makes no feed/Stories request and survives cached tab return',
    (tester) async {
      await show(tester);
      final card = find.byType(PostCard).first;
      final caption = find.descendant(
        of: card,
        matching: find.byType(HomePostCaption),
      );
      Finder rich() =>
          find.descendant(of: caption, matching: find.byType(RichText));
      final paragraph = tester.renderObject<RenderParagraph>(rich());
      final text = paragraph.text.toPlainText(includeSemanticsLabels: false);
      final start = text.lastIndexOf('read more...');
      expect(start, greaterThanOrEqualTo(0));
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + 12),
      );
      final reads = posts.reads.length;
      final storyReads = stories.reads;
      final offset = vertical(tester).offset;
      await tester.tapAt(paragraph.localToGlobal(boxes.first.toRect().center));
      await tester.pumpAndSettle();
      expect(posts.reads, hasLength(reads));
      expect(stories.reads, storyReads);
      expect(vertical(tester).offset, offset);
      expect(
        tester
            .renderObject<RenderParagraph>(rich())
            .text
            .toPlainText(includeSemanticsLabels: false),
        endsWith('show less'),
      );
      await tester.tap(find.text('Following'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('For You'));
      await tester.pumpAndSettle();
      expect(posts.reads, hasLength(reads + 1));
      expect(stories.reads, storyReads);
      expect(
        tester
            .renderObject<RenderParagraph>(rich())
            .text
            .toPlainText(includeSemanticsLabels: false),
        endsWith('show less'),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
