import 'package:travibe/core/constants/app_sizes.dart';
import 'package:shimmer/shimmer.dart';
import 'package:travibe/features/home/widgets/home_loading_skeleton.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/post_card.dart';
import 'package:travibe/core/widgets/travibe_loading_indicator.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/features/home/screens/home_screen.dart';
import 'package:travibe/features/home/widgets/home_tabs.dart';
import 'package:travibe/features/home/widgets/home_top_bar.dart';
import 'package:travibe/features/home/widgets/home_stories.dart';
import 'package:travibe/features/home/widgets/suggested_users_section.dart';
import 'package:travibe/features/follow/cubit/follow_users_cubit.dart';
import 'package:travibe/features/search/data/users_page_model.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/root.dart';
import '../../helpers/cursor_fixtures.dart';
import 'home_experience_fixtures.dart' as home;

class _FeedRead {
  _FeedRead(this.path, this.query);
  final String path;
  final Map<String, dynamic>? query;
  final response = Completer<dynamic>();
}

class _FeedApi extends ApiService {
  final reads = <_FeedRead>[];
  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) {
    final read = _FeedRead(endpoint, queryParameters);
    reads.add(read);
    return read.response.future;
  }

  void finish({String? next, List<int> ids = const [1, 2, 3]}) =>
      reads.last.response.complete(
        cursorEnvelope(
          next: next,
          data: [
            for (final id in ids)
              {
                'id': id,
                'user_id': 7,
                'content': 'Post $id',
                'user': {'id': 7, 'name': 'Traveler'},
              },
          ],
        ),
      );
}

class _PendingStories extends StoriesRepo {
  final pending = Completer<StoriesPage>();
  int reads = 0;
  @override
  Future<StoriesPage> getStories({int page = 1}) {
    reads++;
    return pending.future;
  }
}

void main() {
  setUp(() {
    ScreenUtil.configure(
      data: const MediaQueryData(size: Size(390, 844)),
      designSize: const Size(390, 844),
      minTextAdapt: false,
      splitScreenMode: false,
    );
  });

  late _FeedApi api;
  late home.AccountRepo account;
  late FollowCubit follow;
  late BlockCubit block;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    api = _FeedApi();
    account = home.AccountRepo();
    follow = FollowCubit(repo: home.PeopleRepo(account));
    block = BlockCubit(follow: follow);
  });
  tearDown(() async {
    await block.close();
    await follow.close();
    await PreferencesManager().clear();
  });
  Future<void> show(
    WidgetTester tester, {
    StoriesRepo? stories,
    Listenable? refreshSignal,
    Listenable? publicationSignal,
    bool root = false,
    double topInset = 0,
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding(top: topInset);
    tester.view.viewPadding = FakeViewPadding(top: topInset);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: root
              ? Root(
                  postsRepo: PostsRepo(apiService: api),
                  homeAccountRepo: account,
                  followRepo: home.PeopleRepo(account),
                )
              : Scaffold(
                  body: MultiBlocProvider(
                    providers: [
                      BlocProvider.value(value: follow),
                      BlocProvider.value(value: block),
                    ],
                    child: HomeScreen(
                      storiesRepo: stories,
                      refreshSignal: refreshSignal,
                      publicationSignal: publicationSignal,
                      postsRepo: PostsRepo(apiService: api),
                      accountRepo: account,
                    ),
                  ),
                ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  Finder loader(double size) => find.byWidgetPredicate(
    (w) => w is TravibeLoadingIndicator && w.size == size,
  );

  void expectHomeTopLoader(WidgetTester tester) {
    final spinner = tester.getRect(find.byType(CupertinoActivityIndicator));
    final tabs = tester.getRect(find.byType(HomeTabs));
    expect(spinner.width, 30);
    expect(spinner.height, 30);
    expect(
      spinner.top,
      closeTo(tester.view.padding.top / tester.view.devicePixelRatio, .01),
    );
    expect(spinner.top, lessThanOrEqualTo(tabs.top));
    expect(spinner.center.dx, closeTo(tabs.center.dx, .01));
    expect(
      spinner.center.dy,
      lessThan(
        tester.view.physicalSize.height / tester.view.devicePixelRatio / 2,
      ),
    );
  }

  testWidgets(
    'For You replaces only the feed label; both active dots stay white and 6px',
    (tester) async {
      await show(tester);
      expect(
        find.descendant(
          of: find.byType(HomeTabs),
          matching: find.text('For You'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(HomeTabs),
          matching: find.text('Explore'),
        ),
        findsNothing,
      );
      final firstDot = find.byKey(const ValueKey('home-tab-indicator-0'));
      expect(
        (tester.widget<Container>(firstDot).decoration as BoxDecoration).color,
        Colors.white,
      );
      expect(tester.getSize(firstDot), const Size.square(6));
      final selected = tester.widget<Text>(find.text('For You')).style!;
      final unselected = tester.widget<Text>(find.text('Following')).style!;
      expect(selected.fontWeight, FontWeight.w700);
      expect(selected.color, Colors.white);
      expect(unselected.fontWeight, FontWeight.w400);
      expect(unselected.color, Colors.white54);
      expect(api.reads.single.path, 'feed/explore');
      expect(api.reads.single.query, {'per_page': 15});
      await tester.tap(find.text('Following'));
      await tester.pump();
      final secondDot = find.byKey(const ValueKey('home-tab-indicator-1'));
      expect(firstDot, findsNothing);
      expect(
        (tester.widget<Container>(secondDot).decoration as BoxDecoration).color,
        Colors.white,
      );
      expect(tester.getSize(secondDot), const Size.square(6));
      expect(api.reads.last.path, 'feed/following');
      expect(api.reads.last.query, {'per_page': 15});
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final following in [false, true]) {
    testWidgets(
      '${following ? 'Following' : 'For You'} initial load shows post skeletons without a spinner',
      (tester) async {
        await show(tester);
        if (following) {
          await tester.tap(find.text('Following'));
          await tester.pump();
        }
        expect(find.byType(HomeFeedSkeleton), findsOneWidget);
        expect(loader(30), findsNothing);
        expect(find.byType(CupertinoActivityIndicator), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        api.finish();
        await tester.pumpAndSettle();
        expect(loader(30), findsNothing);
        expect(find.byType(PostCard), findsWidgets);
        expect(find.byType(HomeFeedSkeleton), findsNothing);
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'continuation uses a Cupertino footer and the exact cursor without removing posts',
    (tester) async {
      await show(tester);
      api.finish(next: 'opaque-feed-cursor');
      await tester.pumpAndSettle();
      final scroll = tester.widget<CustomScrollView>(
        find.byType(CustomScrollView),
      );
      scroll.controller!.jumpTo(scroll.controller!.position.maxScrollExtent);
      await tester.pump();
      expect(api.reads.last.query, {
        'per_page': 15,
        'cursor': 'opaque-feed-cursor',
      });
      expect(loader(32), findsWidgets);
      expect(loader(30), findsNothing);
      expect(find.byType(PostCard), findsWidgets);
      expect(find.byType(HomeFeedSkeleton), findsNothing);
      api.finish(ids: [3, 4]);
      await tester.pumpAndSettle();
      expect(loader(32), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'explicit refresh shows the same page-top spinner while retaining post elements',
    (tester) async {
      await show(tester);
      api.finish();
      await tester.pumpAndSettle();
      final card = tester.element(find.byType(PostCard).first);
      final cardBounds = tester.getRect(find.byType(PostCard).first);
      final storiesBounds = tester.getRect(find.byType(HomeStories));
      final headerBounds = tester.getRect(find.byType(HomeTopBar));
      final tabsBounds = tester.getRect(find.byType(HomeTabs));
      expect(cardBounds.top - tabsBounds.bottom, closeTo(16, .01));
      final tabsDelegate = tester
          .widget<SliverPersistentHeader>(
            find.byWidgetPredicate(
              (widget) => widget is SliverPersistentHeader && widget.pinned,
            ),
          )
          .delegate;
      expect(tabsDelegate.minExtent, 48);
      expect(tabsDelegate.maxExtent, 48);
      final refresh = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator),
      );
      final request = refresh.onRefresh();
      await tester.pump();
      await tester.pump();
      expect(api.reads, hasLength(2));
      expect(api.reads.last.query, {'per_page': 15});
      expect(find.byType(TravibeLoadingIndicator), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expectHomeTopLoader(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.element(find.byType(PostCard).first), same(card));
      expect(tester.getRect(find.byType(PostCard).first), cardBounds);
      expect(tester.getRect(find.byType(HomeStories)), storiesBounds);
      expect(tester.getRect(find.byType(HomeTopBar)), headerBounds);
      expect(tester.getRect(find.byType(HomeTabs)), tabsBounds);
      expect(
        tester.getRect(find.byType(PostCard).first).top -
            tester.getRect(find.byType(HomeTabs)).bottom,
        closeTo(16, .01),
      );
      expect(
        tester.getBottomLeft(find.byType(CupertinoActivityIndicator)).dy,
        lessThanOrEqualTo(cardBounds.top),
      );
      expect(find.byType(RefreshProgressIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      api.finish();
      await request;
      await tester.pumpAndSettle();
      expect(find.byType(TravibeLoadingIndicator), findsNothing);
      expect(tester.getRect(find.byType(PostCard).first), cardBounds);
      expect(tester.getRect(find.byType(HomeStories)), storiesBounds);
      expect(tester.getRect(find.byType(HomeTopBar)), headerBounds);
      expect(tester.getRect(find.byType(HomeTabs)), tabsBounds);
      expect(
        tester.getRect(find.byType(PostCard).first).top -
            tester.getRect(find.byType(HomeTabs)).bottom,
        closeTo(16, .01),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final following in [false, true]) {
    testWidgets(
      'post skeletons hide on ${following ? 'Following' : 'For You'} success while Stories/account still load',
      (tester) async {
        await PreferencesManager().saveToken('home-loading-test');
        final stories = _PendingStories();
        account.gate = Completer();
        await show(tester, stories: stories);
        if (following) {
          await tester.tap(find.text('Following'));
          await tester.pump();
        }
        expect(stories.reads, 1);
        expect(find.byType(CupertinoActivityIndicator), findsNothing);
        expect(find.byType(HomeFeedSkeleton), findsOneWidget);
        expect(find.byType(HomeStorySkeleton), findsWidgets);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(HomeTopBar), findsOneWidget);
        expect(find.byType(HomeTabs), findsOneWidget);
        api.finish(ids: []);
        await tester.pumpAndSettle();
        expect(find.byType(CupertinoActivityIndicator), findsNothing);
        expect(find.byType(TravibeLoadingIndicator), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        if (!following) {
          expect(
            tester.widget<HomeStories>(find.byType(HomeStories)).loading,
            true,
          );
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'initial loading keeps the real header, tabs and bottom navigation visible',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            theme: darkTheme,
            home: Root(
              postsRepo: PostsRepo(apiService: api),
              homeAccountRepo: account,
              followRepo: home.PeopleRepo(account),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(find.byType(HomeFeedSkeleton), findsOneWidget);
      expect(find.byType(HomeTopBar), findsOneWidget);
      expect(find.byType(HomeTabs), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(HomeFeedSkeleton)).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.byType(HomeTabs)).dy),
      );
      api.finish();
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Stories retain You and continuation actions without independent spinners',
    (tester) async {
      var more = 0;
      Future<void> stories({
        bool loading = false,
        bool loadingMore = false,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HomeStories(
                stories: const [],
                loading: loading,
                loadingMore: loadingMore,
                hasMore: true,
                onLoadMore: () => more++,
              ),
            ),
          ),
        );
        await tester.pump();
      }

      await stories(loading: true);
      expect(find.text('You'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(find.text('More Stories'), findsNothing);
      await stories(loadingMore: true);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await stories();
      await tester.tap(find.text('More Stories'));
      expect(more, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Home can suppress suggestion spinners while default Search behavior remains',
    (tester) async {
      final pending = Completer<UsersPageModel>();
      final list = FollowUsersCubit(loadPage: (_) => pending.future)..load();
      addTearDown(list.close);
      Future<void> section(bool suppress) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MultiBlocProvider(
                providers: [
                  BlocProvider.value(value: follow),
                  BlocProvider.value(value: block),
                ],
                child: suppress
                    ? SuggestedUsersSection(
                        compact: true,
                        cubit: list,
                        showLoadingIndicators: false,
                      )
                    : SuggestedUsersSection(compact: true, cubit: list),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      await section(true);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await section(false);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'initial failure removes skeletons and retry restores skeletons',
    (tester) async {
      await show(tester);
      api.reads.last.response.completeError(ApiError(message: 'Feed failed'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(find.text('Feed failed'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(find.byType(HomeFeedSkeleton), findsOneWidget);
      api.finish(ids: []);
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'pull gesture shows one page-top spinner with no native-spinner overlap',
    (tester) async {
      await show(tester);
      final initialCenter = Offset(195, tester.view.padding.top + 15);
      api.finish();
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 450));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(api.reads, hasLength(2));
      expect(api.reads.last.query, {'per_page': 15});
      expect(find.byType(RefreshIndicator), findsOneWidget);
      expect(
        tester.getCenter(find.byKey(const ValueKey('home-top-loading'))),
        initialCenter,
      );
      final native = tester.widget<CupertinoActivityIndicator>(
        find.byType(CupertinoActivityIndicator),
      );
      expect(native.radius, 15);
      expect(native.color, DarkColors.primaryColor);
      expect(find.byType(TravibeLoadingIndicator), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expectHomeTopLoader(tester);
      expect(find.byType(RefreshProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(PostCard), findsWidgets);
      expect(find.byType(HomeFeedSkeleton), findsNothing);
      api.finish();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Home re-tap shares initial placement, keeps the selected tab, and coalesces repeated taps',
    (tester) async {
      await show(tester, root: true);
      final initialCenter = Offset(195, tester.view.padding.top + 15);
      api.finish();
      await tester.pumpAndSettle();
      final card = tester.element(find.byType(PostCard).first);
      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text('Home'),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(api.reads, hasLength(2));
      expect(api.reads.last.path, 'feed/explore');
      expect(api.reads.last.query, {'per_page': 15});
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expectHomeTopLoader(tester);
      expect(
        tester.getCenter(find.byKey(const ValueKey('home-top-loading'))),
        initialCenter,
      );
      expect(tester.element(find.byType(PostCard).first), same(card));
      tester
          .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
          .onTap!(0);
      tester
          .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
          .onTap!(0);
      await tester.pump();
      expect(api.reads, hasLength(2));
      api.finish();
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      await tester.tap(find.text('Following').first);
      await tester.pump();
      api.finish(ids: [21, 22, 23]);
      await tester.pumpAndSettle();
      final followingCard = tester.element(find.byType(PostCard).first);
      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text('Home'),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(api.reads.last.path, 'feed/following');
      expect(tester.element(find.byType(PostCard).first), same(followingCard));
      expect(
        tester.widget<Text>(find.text('Following').first).style!.fontWeight,
        FontWeight.w700,
      );
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expectHomeTopLoader(tester);
      api.finish(ids: [21, 22, 23]);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'returning Home from another bottom tab reuses content without a refresh',
    (tester) async {
      await show(tester, root: true);
      api.finish();
      await tester.pumpAndSettle();
      final card = tester.element(find.byType(PostCard).first);
      tester
          .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
          .onTap!(1);
      await tester.pumpAndSettle();
      tester
          .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
          .onTap!(0);
      await tester.pumpAndSettle();
      expect(api.reads, hasLength(1));
      expect(tester.element(find.byType(PostCard).first), same(card));
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'explicit refresh retains scroll and card state, permits scrolling, and clears on failure',
    (tester) async {
      final signal = ValueNotifier<int>(0);
      addTearDown(signal.dispose);
      await show(tester, refreshSignal: signal);
      api.finish(ids: List.generate(10, (i) => i + 1));
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      scroll.jumpTo(80);
      await tester.pumpAndSettle();
      final card = tester.element(find.byType(PostCard).first);
      signal.value++;
      await tester.pump();
      await tester.pump();
      expect(scroll.offset, 80);
      expect(tester.element(find.byType(PostCard).first), same(card));
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expectHomeTopLoader(tester);
      expect(
        tester
            .widget<IgnorePointer>(
              find
                  .ancestor(
                    of: find.byKey(const ValueKey('home-top-loading')),
                    matching: find.byType(IgnorePointer),
                  )
                  .first,
            )
            .ignoring,
        true,
      );
      scroll.jumpTo(100);
      await tester.pump();
      expect(scroll.offset, 100);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('home-top-loading'))).dy,
        lessThan(tester.getTopLeft(find.byType(HomeTabs)).dy),
      );
      api.reads.last.response.completeError(
        ApiError(message: 'Refresh failed'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(scroll.offset, 100);
      expect(find.byType(PostCard), findsWidgets);
      expect(find.byType(HomeFeedSkeleton), findsNothing);
      expect(find.text('Refresh failed'), findsOneWidget);
      signal.value++;
      await tester.pump();
      expect(api.reads.last.query, {'per_page': 15});
      api.finish(ids: List.generate(10, (i) => i + 1));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'explicit refresh supersedes pagination and restarts its cursor without two indicators',
    (tester) async {
      final signal = ValueNotifier<int>(0);
      addTearDown(signal.dispose);
      await show(tester, refreshSignal: signal);
      api.finish(next: 'old-cursor', ids: List.generate(10, (i) => i + 1));
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      final oldMore = api.reads.last;
      expect(oldMore.query!['cursor'], 'old-cursor');
      expect(find.byKey(const ValueKey('home-top-loading')), findsNothing);
      signal.value++;
      await tester.pump();
      await tester.pump();
      expect(api.reads.last.query, {'per_page': 15});
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expectHomeTopLoader(tester);
      oldMore.response.complete(
        cursorEnvelope(
          data: [
            {'id': 999, 'content': 'Stale post'},
          ],
          next: 'stale-cursor',
        ),
      );
      await tester.pump();
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expectHomeTopLoader(tester);
      api.finish(next: 'new-cursor', ids: List.generate(10, (i) => i + 1));
      await tester.pumpAndSettle();
      expect(find.text('Stale post'), findsNothing);
      expect(find.byKey(const ValueKey('home-top-loading')), findsNothing);
      scroll.jumpTo(0);
      await tester.pump();
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      expect(api.reads.last.query!['cursor'], 'new-cursor');
      api.finish(ids: [11]);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'background publication refresh never displays the page-top indicator',
    (tester) async {
      final signal = ValueNotifier<int>(0);
      addTearDown(signal.dispose);
      await show(tester, publicationSignal: signal);
      api.finish();
      await tester.pumpAndSettle();
      signal.value++;
      await tester.pump();
      await tester.pump();
      expect(find.byType(PostCard), findsWidgets);
      expect(find.byType(HomeFeedSkeleton), findsNothing);
      expect(find.byKey(const ValueKey('home-top-loading')), findsNothing);
      for (final read in api.reads.skip(1)) {
        read.response.complete(
          cursorEnvelope(
            data: [
              {'id': 1, 'content': 'Post 1'},
            ],
          ),
        );
      }
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'session switch invalidates explicit overlay completion and old feed data',
    (tester) async {
      final signal = ValueNotifier<int>(0);
      addTearDown(signal.dispose);
      await PreferencesManager().saveToken('session-A');
      await show(tester, refreshSignal: signal, stories: _PendingStories());
      api.finish();
      await tester.pumpAndSettle();
      signal.value++;
      await tester.pump();
      final old = api.reads.last;
      await PreferencesManager().saveToken('session-B');
      await tester.pump();
      await tester.pump();
      old.response.complete(
        cursorEnvelope(
          data: [
            {'id': 999, 'content': 'Old account post'},
          ],
        ),
      );
      await tester.pump();
      expect(find.text('Old account post'), findsNothing);
      final freshReads = api.reads
          .where((r) => r != old && !r.response.isCompleted)
          .toList();
      for (final read in freshReads) {
        expect(read.query, {'per_page': 15});
        read.response.complete(
          cursorEnvelope(
            data: [
              {
                'id': 50,
                'content': 'New account post',
                'user': {'id': 8},
              },
            ],
          ),
        );
      }
      await tester.pumpAndSettle();
      expect(find.text('New account post'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-top-loading')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'pending explicit refresh can finish after disposal and listeners are removed',
    (tester) async {
      final signal = ValueNotifier<int>(0);
      addTearDown(signal.dispose);
      await show(tester, refreshSignal: signal);
      api.finish();
      await tester.pumpAndSettle();
      signal.value++;
      await tester.pump();
      final request = api.reads.last;
      await tester.pumpWidget(const SizedBox());
      signal.value++;
      request.response.complete(cursorEnvelope(data: []));
      await tester.pump();
      expect(api.reads, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'returning Home before its first request completes does not restart it',
    (tester) async {
      await show(tester, root: true);
      tester
          .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
          .onTap!(1);
      await tester.pump();
      tester
          .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
          .onTap!(0);
      await tester.pump();
      await tester.pump();
      expect(api.reads, hasLength(1));
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(find.byType(HomeFeedSkeleton), findsOneWidget);
      api.finish();
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'pull and Home re-tap share a floating page-top position below the status bar',
    (tester) async {
      await show(tester, root: true, topInset: 44);
      expect(find.byType(HomeFeedSkeleton), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      const position = Rect.fromLTWH(180, 44, 30, 30);
      api.finish();
      await tester.pumpAndSettle();
      final stories = tester.getRect(find.byType(HomeStories));
      final tabs = tester.getRect(find.byType(HomeTabs));
      final post = tester.getRect(find.byType(PostCard).first);
      expect(post.top - tabs.bottom, closeTo(16, .01));
      final request = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pump();
      await tester.pump();
      expect(tester.getRect(find.byType(CupertinoActivityIndicator)), position);
      expect(tester.getRect(find.byType(HomeStories)), stories);
      expect(tester.getRect(find.byType(HomeTabs)), tabs);
      expect(tester.getRect(find.byType(PostCard).first), post);
      api.finish();
      await request;
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text('Home'),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.getRect(find.byType(CupertinoActivityIndicator)), position);
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(find.byType(RefreshProgressIndicator), findsNothing);
      expect(tester.getRect(find.byType(HomeStories)), stories);
      expect(tester.getRect(find.byType(HomeTabs)), tabs);
      expect(tester.getRect(find.byType(PostCard).first), post);
      api.finish();
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(HomeStories)), stories);
      expect(tester.getRect(find.byType(HomeTabs)), tabs);
      expect(tester.getRect(find.byType(PostCard).first), post);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'reference tabs are centered with a compact 16px gap and right-aligned Search',
    (tester) async {
      await show(tester);
      expect(
        tester.getSize(find.byKey(const ValueKey('home-feed-tab-gap'))).width,
        16,
      );
      final first = tester.getRect(find.text('For You'));
      final second = tester.getRect(find.text('Following'));
      final search = tester.getRect(
        find.byKey(const ValueKey('home-search-icon')),
      );
      expect(
        tester.getCenter(find.byKey(const ValueKey('home-feed-tab-group'))).dx,
        195,
      );
      expect((first.left + second.right) / 2, closeTo(195, 1));
      expect(second.left - first.right, closeTo(16, 4));
      expect(second.right, lessThan(search.left));
      expect(search.center.dy, closeTo(first.center.dy, 1));
      expect(search.center.dy, closeTo(second.center.dy, 1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'story and post bones match reference geometry and dark reduced-motion styling',
    (tester) async {
      await PreferencesManager().saveToken('skeleton-session');
      final stories = _PendingStories();
      await show(tester, stories: stories);
      expect(
        tester.getSize(
          find.byKey(const ValueKey('story-skeleton-avatar')).first,
        ),
        const Size.square(64),
      );
      final ring = find.byKey(const ValueKey('story-skeleton-ring')).first;
      expect(tester.getSize(ring), const Size.square(72));
      expect(
        (tester.widget<Container>(ring).decoration as BoxDecoration).shape,
        BoxShape.circle,
      );
      expect(
        tester.getSize(
          find.byKey(const ValueKey('post-skeleton-avatar')).first,
        ),
        const Size.square(40),
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('post-skeleton-media')).first)
            .height,
        220,
      );
      for (final part in ['author', 'timestamp', 'caption', 'actions']) {
        expect(find.byKey(ValueKey('post-skeleton-$part')), findsNWidgets(2));
      }
      for (final shimmer in tester.widgetList<Shimmer>(find.byType(Shimmer))) {
        expect(shimmer.enabled, false);
        expect((shimmer.gradient as LinearGradient).colors.toSet(), {
          const Color(0xFF232323),
          const Color(0xFF303030),
        });
      }
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(find.byType(PostCard), findsNothing);
      api.finish(ids: []);
      await tester.pumpAndSettle();
      expect(find.byType(HomeFeedSkeleton), findsNothing);
      expect(find.byType(HomeStorySkeleton), findsWidgets);
      stories.pending.complete(
        StoriesPage.fromJson({
          'data': [],
          'meta': {
            'current_page': 1,
            'last_page': 1,
            'per_page': 15,
            'total': 0,
          },
          'links': {'next': null},
        }),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HomeStorySkeleton), findsNothing);
      expect(find.text('No posts yet'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'uncached tab skeletons preserve Stories scroll and cached feed without extra reads',
    (tester) async {
      await PreferencesManager().saveToken('stories-cache');
      final stories = _PendingStories();
      await show(tester, stories: stories);
      stories.pending.complete(
        StoriesPage.fromJson({
          'meta': {
            'current_page': 1,
            'last_page': 1,
            'per_page': 15,
            'total': 10,
          },
          'links': {'next': null},
          'data': List.generate(
            10,
            (i) => {
              'user': {'id': i + 20, 'name': 'Traveler $i'},
              'has_unseen': true,
              'stories': [
                {
                  'id': i + 1,
                  'expires_at': '2030-11-03T00:00:00Z',
                  'views_count': 0,
                  'has_seen': false,
                },
              ],
            },
          ),
        }),
      );
      api.finish();
      await tester.pumpAndSettle();
      final header = tester.element(find.byType(HomeStories));
      final list = find.descendant(
        of: find.byType(HomeStories),
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(list).position;
      position.jumpTo(170);
      await tester.pump();
      await tester.tap(find.text('Following'));
      await tester.pump();
      expect(find.byType(HomeFeedSkeleton), findsOneWidget);
      expect(find.byType(HomeStorySkeleton), findsNothing);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(tester.element(find.byType(HomeStories)), same(header));
      expect(tester.state<ScrollableState>(list).position, same(position));
      expect(position.pixels, 170);
      await tester.tap(find.text('For You'));
      await tester.pump();
      expect(find.byType(PostCard), findsWidgets);
      expect(find.byType(HomeFeedSkeleton), findsNothing);
      await tester.tap(find.text('Following'));
      await tester.pump();
      expect(api.reads, hasLength(2));
      expect(stories.reads, 1);
      expect(position.pixels, 170);
      api.finish(ids: []);
      await tester.pumpAndSettle();
      expect(find.byType(HomeFeedSkeleton), findsNothing);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
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
      testWidgets('initial skeletons fit $size at text scale $scale', (
        tester,
      ) async {
        await PreferencesManager().saveToken('responsive-skeleton');
        await show(
          tester,
          stories: _PendingStories(),
          size: size,
          textScale: scale,
        );
        expect(find.byType(HomeFeedSkeleton), findsOneWidget);
        expect(find.byType(HomeStorySkeleton), findsWidgets);
        expect(find.byType(CupertinoActivityIndicator), findsNothing);
        final first = tester.getRect(find.text('For You'));
        final second = tester.getRect(find.text('Following'));
        final search = tester.getRect(
          find.byKey(const ValueKey('home-search-icon')),
        );
        expect(first.center.dy, closeTo(second.center.dy, .1));
        expect(search.center.dy, closeTo(first.center.dy, .1));
        expect(second.right, lessThan(search.left));
        expect(
          tester
              .getCenter(find.byKey(const ValueKey('home-feed-tab-group')))
              .dx,
          closeTo(size.width / 2, .01),
        );
        final searchTarget = tester.getRect(
          find.byKey(const ValueKey('home-search')),
        );
        final tabsRect = tester.getRect(find.byType(HomeTabs));
        expect(
          searchTarget.right,
          closeTo(tabsRect.right - AppSizes.adaptiveWidth(20), .01),
        );
        for (final name in ['story-skeleton-avatar', 'story-skeleton-ring']) {
          final rect = tester.getSize(find.byKey(ValueKey(name)).first);
          expect(rect.width, rect.height);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets(
    'skeleton shimmer animates normally and excludes decorative semantics',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: const HomeFeedSkeleton()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.widget<Shimmer>(find.byType(Shimmer).first).enabled, true);
      expect(find.byType(ExcludeSemantics), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final following in [false, true]) {
    for (final content in ['long', 'short', 'empty', 'initial']) {
      testWidgets(
        'full page pulls together on ${following ? 'Following' : 'For You'} with $content feed',
        (tester) async {
          account.followingCount = 3;
          await show(tester, root: true);
          final ids = content == 'empty'
              ? <int>[]
              : List.generate(content == 'long' ? 10 : 1, (i) => i + 1);
          if (content != 'initial') {
            api.finish(ids: ids);
            await tester.pumpAndSettle();
          }
          if (following) {
            await tester.tap(find.text('Following'));
            await tester.pump();
            if (content != 'initial') {
              api.finish(ids: ids);
              await tester.pumpAndSettle();
            }
          }
          final moving = [
            find.byType(HomeTopBar),
            find.byType(HomeStories),
            find.descendant(
              of: find.byType(HomeStories),
              matching: find.text('You'),
            ),
            find.byType(HomeTabs),
            if (content == 'initial') find.byType(HomeFeedSkeleton),
            if (content == 'short' || content == 'long')
              find.byType(PostCard).first,
          ];
          final before = moving.map(tester.getRect).toList();
          final bottom = tester.getRect(find.byType(BottomNavigationBar));
          final reads = api.reads.length;
          final gesture = await tester.startGesture(
            Offset(40, before.first.center.dy),
          );
          await gesture.moveBy(const Offset(0, 180));
          await tester.pump();
          final delta = tester.getRect(moving.first).top - before.first.top;
          expect(delta, greaterThan(20));
          for (var index = 0; index < moving.length; index++) {
            expect(
              tester.getRect(moving[index]).top - before[index].top,
              closeTo(delta, .1),
            );
          }
          expect(tester.getRect(find.byType(BottomNavigationBar)), bottom);
          // Pulling never starts cursor pagination or a first-page read early.
          expect(api.reads, hasLength(reads));
          await gesture.up();
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          expect(api.reads, hasLength(reads + (content == 'initial' ? 0 : 1)));
          expectHomeTopLoader(tester);
          expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
          expect(find.byType(RefreshProgressIndicator), findsNothing);
          if (content != 'initial') {
            expect(find.byType(HomeFeedSkeleton), findsNothing);
          }
          api.finish(ids: ids);
          await tester.pumpAndSettle();
          expect(find.byType(CupertinoActivityIndicator), findsNothing);
          expect(tester.getRect(find.byType(HomeTopBar)), before.first);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  for (final origin in ['greeting', 'stories', 'names', 'tabs', 'posts']) {
    testWidgets(
      'vertical refresh starts over $origin without a second vertical scrollable',
      (tester) async {
        await show(tester);
        api.finish(ids: [1]);
        await tester.pumpAndSettle();
        final target = switch (origin) {
          'greeting' => find.byType(HomeTopBar),
          'stories' => find.byKey(const ValueKey('story-avatar-you')),
          'names' => find.descendant(
            of: find.byType(HomeStories),
            matching: find.text('You'),
          ),
          'tabs' => find.text('For You'),
          _ => find.byType(PostCard).first,
        };
        final point = tester.getCenter(target);
        final gesture = await tester.startGesture(point);
        await gesture.moveBy(const Offset(0, 30));
        await tester.pump();
        await gesture.moveBy(const Offset(0, 220));
        await tester.pump();
        await gesture.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(api.reads, hasLength(2));
        expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
        final vertical = tester
            .widgetList<Scrollable>(find.byType(Scrollable))
            .where((widget) => widget.axis == Axis.vertical);
        expect(vertical, hasLength(1));
        api.finish(ids: [1]);
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'horizontal Stories scrolling retains its offset without refreshing Home',
    (tester) async {
      await PreferencesManager().saveToken('horizontal-stories');
      final stories = _PendingStories();
      await show(tester, stories: stories);
      stories.pending.complete(
        StoriesPage.fromJson({
          'data': List.generate(
            10,
            (i) => {
              'user': {'id': i + 20, 'name': 'Traveler $i'},
              'has_unseen': true,
              'stories': [
                {
                  'id': i + 1,
                  'expires_at': '2030-11-03T00:00:00Z',
                  'views_count': 0,
                  'has_seen': false,
                },
              ],
            },
          ),
          'meta': {
            'current_page': 1,
            'last_page': 1,
            'per_page': 15,
            'total': 10,
          },
          'links': {'next': null},
        }),
      );
      api.finish(ids: [1]);
      await tester.pumpAndSettle();
      final list = find.descendant(
        of: find.byType(HomeStories),
        matching: find.byType(ListView),
      );
      await tester.drag(list, const Offset(-240, 0));
      await tester.pumpAndSettle();
      final position = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(HomeStories),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      expect(position.pixels, greaterThan(0));
      expect(api.reads, hasLength(1));
      expect(stories.reads, 1);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(
        tester
            .widget<CustomScrollView>(find.byType(CustomScrollView))
            .controller!
            .offset,
        0,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
