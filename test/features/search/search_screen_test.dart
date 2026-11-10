import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/screens/follow_users_screen.dart';
import 'package:travibe/features/home/widgets/home_tabs.dart';
import 'package:travibe/features/home/widgets/suggested_user_card.dart';
import 'package:travibe/features/home/widgets/home_user_avatar.dart';
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
            child: SearchScreen(repo: repo),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
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
    await tester.enterText(find.byType(TextField), 'sarah');
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
    repo.recents = ['sarah', 'bali'];
    await show(tester);
    await tester.tap(find.text('sarah'));
    await tester.pumpAndSettle();
    expect(repo.queries, ['sarah:1']);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear All'));
    await tester.pumpAndSettle();
    expect(find.text('Recent Searches'), findsNothing);
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
          for (final label in ['Top', 'Recent', 'People']) {
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
              expect(
                find.textContaining('Post search is coming soon.'),
                findsOneWidget,
              );
            }
          }
          expect(repo.queries, ['traveler:1']);
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
    for (final label in ['Top', 'Recent', 'People']) {
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
}
