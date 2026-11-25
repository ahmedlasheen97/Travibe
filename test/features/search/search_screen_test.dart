import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/block/data/block_repo.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/screens/follow_users_screen.dart';
import 'package:travibe/features/home/widgets/home_tabs.dart';
import 'package:travibe/features/home/widgets/suggested_user_card.dart';
import 'package:travibe/features/home/widgets/home_user_avatar.dart';
import 'package:travibe/core/widgets/post_card.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/home/data/posts_page_model.dart';
import 'package:travibe/features/home/screens/post_screen.dart';
import 'package:travibe/features/home/widgets/post_options_sheet.dart';
import 'package:travibe/features/profile/widgets/profile_shimmer.dart';
import 'package:travibe/features/search/data/recent_search.dart';
import 'package:travibe/features/search/data/users_page_model.dart';
import 'package:travibe/features/search/screens/search_screen.dart';
import 'package:travibe/features/search/widgets/person_result_tile.dart';
import 'package:travibe/features/search/widgets/search_tabs.dart';
import '../home/home_experience_fixtures.dart';
import 'search_fixtures.dart';

void main() {
  late SearchFixture repo;
  late PeopleRepo people;
  late FollowCubit follow;
  late BlockCubit block;
  setUp(() {
    repo = SearchFixture();
    people = PeopleRepo(AccountRepo());
    follow = FollowCubit(repo: people);
    block = BlockCubit(follow: follow);
  });
  tearDown(() async {
    await block.close();
    await follow.close();
  });

  Future<void> show(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double textScale = 1,
    TextDirection direction = TextDirection.ltr,
    ValueChanged<String>? onOpenProfile,
    ValueChanged<PostModel>? onOpenPost,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: Directionality(textDirection: direction, child: child!),
          ),
          home: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: follow),
              BlocProvider.value(value: block),
            ],
            child: SearchScreen(
              repo: repo,
              onOpenProfile: onOpenProfile,
              onOpenPost: onOpenPost,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> peopleTab(WidgetTester tester) async {
    final tab = find.descendant(
      of: find.byType(SearchTabs),
      matching: find.text('People'),
    );
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab);
    await tester.pumpAndSettle();
  }

  /// Submits [query] and shows the People tab (Posts is the default).
  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    if (find.byType(SearchTabs).evaluate().isNotEmpty) await peopleTab(tester);
  }

  testWidgets(
    'empty input uses Home cards and excludes self, blocked and duplicates',
    (tester) async {
      people.suggestions = [
        suggested('1'),
        suggested('2'),
        suggested('2'),
        suggested('3').copyWith(isBlocked: true),
      ];
      await show(tester);
      expect(find.text('Suggested for You'), findsOneWidget);
      expect(find.byType(SuggestedUserCard), findsOneWidget);
      expect(repo.queries, isEmpty);
      expect(find.text('0 followers'), findsNothing);
      expect(find.text('Block'), findsNothing);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.autofocus, isTrue);
      final svgs = tester.widgetList<SvgPicture>(find.byType(SvgPicture));
      expect(
        svgs.any(
          (svg) =>
              svg.bytesLoader is SvgAssetLoader &&
              (svg.bytesLoader as SvgAssetLoader).assetName ==
                  'assets/images/interactions/search-normal.svg',
        ),
        isTrue,
      );
    },
  );
  testWidgets(
    'search submission renders results and clear restores suggestions',
    (tester) async {
      await show(tester);
      await search(tester, 'sarah');
      expect(find.byType(PersonResultTile), findsOneWidget);
      expect(find.text('Sarah Travels'), findsOneWidget);
      expect(repo.queries, ['sarah:1']);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.byType(PersonResultTile), findsNothing);
      expect(find.byType(SuggestedUserCard), findsOneWidget);
      expect(repo.queries, ['sarah:1']);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    },
  );
  testWidgets('no results displays the searched query', (tester) async {
    repo.handler = (_, _) async => usersPage(empty: true);
    await show(tester);
    await search(tester, 'nobody');
    expect(find.text('No people found for “nobody”'), findsOneWidget);
    expect(find.byType(PersonResultTile), findsNothing);
  });
  testWidgets('loading shows progress and failure offers clean retry', (
    tester,
  ) async {
    final pending = Completer<UsersPageModel>();
    repo.handler = (_, _) => pending.future;
    await show(tester);
    await tester.enterText(find.byType(TextField), '@sarah');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(ApiError(message: 'Search unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('Search unavailable'), findsOneWidget);
    expect(find.textContaining('ApiError'), findsNothing);
    repo.handler = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(PersonResultTile), findsOneWidget);
  });
  testWidgets(
    'suggestions use shared follow state and suppress duplicate requests',
    (tester) async {
      people.mutationGate = Completer();
      await show(tester);
      await tester.tap(find.text('Follow'));
      await tester.pump();
      await follow.toggle('2', currentlyFollowing: false);
      expect(people.mutations, 1);
      people.mutationGate!.complete(suggested('2').copyWith(isFollowing: true));
      await tester.pumpAndSettle();
      expect(find.text('Following'), findsOneWidget);
      people.mutationGate = null;
      await tester.tap(find.text('Following'));
      await tester.pumpAndSettle();
      expect(find.text('Follow'), findsOneWidget);
      expect(people.mutations, 2);
    },
  );
  testWidgets('See All opens existing discovery and back restores search', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.text('See All'));
    await tester.pumpAndSettle();
    expect(find.byType(FollowUsersScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(FollowUsersScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);
  });
  testWidgets('recents select, remove and clear without extra empty searches', (
    tester,
  ) async {
    repo.recents = const [RecentSearch('sarah'), RecentSearch('bali')];
    await show(tester);
    await tester.tap(find.text('sarah'));
    await tester.pumpAndSettle();
    expect(repo.postQueries, ['posts:sarah:1']);
    expect(repo.queries, isEmpty);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear All'));
    await tester.pumpAndSettle();
    expect(find.text('Recent Searches'), findsNothing);
  });
  testWidgets('recent section is hidden without history', (tester) async {
    await show(tester);
    expect(find.text('Recent Searches'), findsNothing);
    expect(find.text('Clear All'), findsNothing);
    expect(find.text('Search for travelers, posts..'), findsOneWidget);
    expect(find.text('Suggested for You'), findsOneWidget);
  });
  testWidgets('X removes only that recent', (tester) async {
    repo.recents = const [RecentSearch('sarah'), RecentSearch('bali')];
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('recent-search-remove-0')));
    await tester.pumpAndSettle();
    expect(find.text('sarah'), findsNothing);
    expect(find.text('bali'), findsOneWidget);
    expect(repo.recentTexts, ['bali']);
    expect(repo.queries, isEmpty);
  });
  testWidgets('a submitted query appears in recents after clearing the field', (
    tester,
  ) async {
    await show(tester);
    await search(tester, 'bali');
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Recent Searches'), findsOneWidget);
    expect(find.byKey(const ValueKey('recent-search-0')), findsOneWidget);
    expect(repo.recentTexts, ['bali']);
  });
  testWidgets('opening a person saves @username; the row opens the profile', (
    tester,
  ) async {
    final opened = <String>[];
    await show(tester, onOpenProfile: opened.add);
    await search(tester, 'sarah');
    await tester.tap(find.byType(PersonResultTile));
    await tester.pumpAndSettle();
    expect(opened, ['2']);
    expect(repo.recents.first, const RecentSearch('@traveller', userId: '2'));

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    final queries = List.of(repo.queries);
    await tester.tap(find.byKey(const ValueKey('recent-search-0')));
    await tester.pumpAndSettle();
    expect(opened, ['2', '2']);
    expect(repo.queries, queries);
  });
  testWidgets('small screen handles long names, missing avatars and keyboard', (
    tester,
  ) async {
    people.suggestions = [
      suggested('2', name: 'Long name ' * 15, username: 'long_username' * 10),
    ];
    await show(tester, size: const Size(320, 480));
    expect(find.byType(HomeUserAvatar), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.viewInsets = const FakeViewPadding(bottom: 180);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await search(tester, 'sarah');
    expect(tester.takeException(), isNull);
  });
  for (final width in [320.0, 375.0, 393.0, 430.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'Search fits ${width}px with text scale $scale and keyboard',
        (tester) async {
          people.suggestions = [
            suggested('2', name: 'Long name ' * 15, username: 'handle' * 20),
          ];
          repo.handler = (_, _) async => UsersPageModel(
            users: people.suggestions,
            currentPage: 1,
            lastPage: 1,
            total: 1,
          );
          await show(tester, size: Size(width, 480), textScale: scale);
          expect(tester.takeException(), isNull);
          tester.view.viewInsets = const FakeViewPadding(bottom: 180);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpAndSettle();
          await search(tester, 'traveler');
          expect(find.byType(PersonResultTile), findsOneWidget);
          expect(tester.takeException(), isNull);
          expect(
            tester.getBottomRight(find.byType(TextField)).dy,
            lessThanOrEqualTo(300),
          );
          for (final label in ['Posts', 'People']) {
            final tab = find.descendant(
              of: find.byType(SearchTabs),
              matching: find.text(label),
            );
            await tester.ensureVisible(tab);
            await tester.pumpAndSettle();
            await tester.tap(tab);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            if (label == 'People') {
              expect(find.byType(PersonResultTile), findsOneWidget);
            } else {
              expect(find.text('No posts found'), findsOneWidget);
            }
          }
          expect(repo.queries, ['traveler:1']);
          expect(repo.postQueries, ['posts:traveler:1']);
        },
      );
    }
  }
  testWidgets('RTL Search tabs remain reachable with large text and keyboard', (
    tester,
  ) async {
    await show(
      tester,
      size: const Size(320, 480),
      textScale: 2,
      direction: TextDirection.rtl,
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 180);
    addTearDown(tester.view.resetViewInsets);
    await search(tester, 'sarah');
    for (final label in ['Posts', 'People']) {
      final tab = find.descendant(
        of: find.byType(SearchTabs),
        matching: find.text(label),
      );
      await tester.ensureVisible(tab);
      await tester.pumpAndSettle();
      await tester.tap(tab);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(find.byType(PersonResultTile), findsOneWidget);
    expect(repo.queries, ['sarah:1']);
  });
  for (final width in [390.0, 320.0, 375.0, 393.0, 430.0]) {
    testWidgets(
      'Home search SVG keeps its original colors and tap action${width == 390 ? '' : ' at ${width}px'}',
      (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var taps = 0;
        await tester.pumpWidget(
          ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, _) => MaterialApp(
              home: Scaffold(
                body: HomeTabs(
                  selectedIndex: 0,
                  onTabSelected: (_) {},
                  onSearchTap: () => taps++,
                ),
              ),
            ),
          ),
        );
        final icon = tester.widget<SvgPicture>(find.byType(SvgPicture));
        expect(icon.width, 20);
        expect(icon.height, 20);
        expect(tester.getSize(find.byType(SvgPicture)), const Size(20, 20));
        expect(
          tester.getSize(find.byKey(const ValueKey('home-search'))).width,
          greaterThanOrEqualTo(44),
        );
        expect(icon.colorFilter, isNull);
        await tester.tap(find.byType(SvgPicture));
        expect(taps, 1);
      },
    );
  }

  group('Posts tab', () {
    Future<void> type(WidgetTester tester, String query) async {
      await tester.enterText(find.byType(TextField), query);
      await tester.testTextInput.receiveAction(TextInputAction.search);
    }

    testWidgets('is the default tab and shows a skeleton, then shared '
        'post cards', (tester) async {
      final pending = Completer<PostsPageModel>();
      repo.postsHandler = (_, _) => pending.future;
      await show(tester);
      await type(tester, 'bali');
      await tester.pump();
      expect(find.byType(ProfilePostSkeleton), findsWidgets);
      expect(find.byType(PostCard), findsNothing);
      pending.complete(postsPage([1, 2]));
      await tester.pumpAndSettle();
      expect(find.byType(ProfilePostSkeleton), findsNothing);
      expect(find.byType(PostCard), findsWidgets);
      expect(find.text('Bali sunset 1'), findsOneWidget);
      expect(find.text('Traveler 9'), findsWidgets);
      expect(repo.postQueries, ['posts:bali:1']);
      expect(repo.queries, isEmpty);
    });

    testWidgets('tapping a post opens it; ⋮ opens the options sheet', (
      tester,
    ) async {
      repo.postsHandler = (_, _) async => postsPage([1]);
      final opened = <String>[];
      await show(tester, onOpenPost: (post) => opened.add(post.id));
      await type(tester, 'bali');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bali sunset 1'));
      await tester.pumpAndSettle();
      expect(opened, ['1']);

      await tester.tap(find.byKey(const ValueKey('post-more')));
      await tester.pumpAndSettle();
      expect(find.byType(PostOptionsSheet), findsOneWidget);
      expect(find.byType(PostScreen), findsNothing);
      expect(opened, ['1']);
    });

    testWidgets('no matches shows "No posts found"', (tester) async {
      await show(tester);
      await type(tester, 'nowhere');
      await tester.pumpAndSettle();
      expect(find.text('No posts found'), findsOneWidget);
      expect(find.byType(PostCard), findsNothing);
    });

    testWidgets('empty or short queries never request posts', (tester) async {
      await show(tester);
      for (final query in ['', '   ', 'ab']) {
        await type(tester, query);
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.pumpAndSettle();
      expect(repo.postQueries, isEmpty);
      expect(find.text('Type at least 3 characters to search'), findsOneWidget);
    });

    testWidgets('scrolling near the end loads the next page', (tester) async {
      repo.postsHandler = (_, page) async => page == 1
          ? postsPage([for (var i = 1; i <= 6; i++) i], last: 2)
          : postsPage([7, 8], page: 2, last: 2);
      await show(tester);
      await type(tester, 'bali');
      await tester.pumpAndSettle();
      expect(repo.postQueries, ['posts:bali:1']);
      await tester.scrollUntilVisible(
        find.text('Bali sunset 8'),
        400,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('search-posts-list')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(repo.postQueries, ['posts:bali:1', 'posts:bali:2']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('failure offers retry', (tester) async {
      repo.postsHandler = (_, _) async =>
          throw ApiError(message: 'Search unavailable');
      await show(tester);
      await type(tester, 'bali');
      await tester.pumpAndSettle();
      expect(find.text('Search unavailable'), findsOneWidget);
      repo.postsHandler = (_, _) async => postsPage([1]);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Bali sunset 1'), findsOneWidget);
    });

    testWidgets("blocked authors' posts are hidden", (tester) async {
      repo.postsHandler = (_, _) async => postsPage([1]);
      await block.close();
      block = BlockCubit(follow: follow, repo: _Blocks());
      expect(await block.setBlocked('9', true), isNull);
      await show(tester);
      await type(tester, 'bali');
      await tester.pumpAndSettle();
      expect(find.byType(PostCard), findsNothing);
      expect(find.text('No posts found'), findsOneWidget);
    });
  });
}

class _Blocks extends BlockRepo {
  @override
  Future<PublicUserModel> setBlocked(String id, bool blocked) async =>
      suggested(id).copyWith(isBlocked: blocked);
}
