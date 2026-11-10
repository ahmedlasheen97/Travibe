import '../../helpers/cursor_fixtures.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/create_post/screens/create_post_screen.dart';
import 'package:travibe/features/home/cubit/posts_cubit.dart';
import 'package:travibe/features/home/data/posts_page_model.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/home/widgets/home_tabs.dart';
import 'package:travibe/root.dart';
import 'fixtures.dart';
import '../home/home_experience_fixtures.dart' as home;

class Feeds extends PostsRepo {
  final calls = <FeedType>[];
  @override
  Future<PostsPageModel> getPosts({
    FeedType feed = FeedType.explore,
    String? cursor,
    int perPage = 15,
  }) async {
    calls.add(feed);
    return PostsPageModel(
      pagination: fixtureMeta(current: 1, last: 1),
      posts: [],
      currentPage: 1,
      lastPage: 1,
      total: 0,
    );
  }
}

void main() {
  late MemoryCreatePostRepo repo;
  PostModel? result;
  setUp(() {
    repo = MemoryCreatePostRepo();
    result = null;
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await CreatePostScreen.open(context, repo: repo);
                },
                child: const Text('Compose'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Compose'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'validates input, counts Unicode text and offers only supported audiences',
    (tester) async {
      await open(tester);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(find.text('Sara'), findsOneWidget);
      expect(find.text('@sara'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '😀 Trip');
      await tester.pump();
      expect(find.text('6/2000'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      await tester.tap(find.text('Public'));
      await tester.pumpAndSettle();
      expect(find.text('Mutuals'), findsNothing);
      expect(find.byKey(const ValueKey('audience-followers')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('audience-private')));
      await tester.pumpAndSettle();
      expect(find.text('Private'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'x' * 2001);
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed publication keeps the draft and audience for retry', (
    tester,
  ) async {
    repo.error = ApiError(message: 'The content is invalid.', statusCode: 422);
    await open(tester);
    await tester.enterText(find.byType(TextField), 'My draft');
    await tester.pump();
    await tester.tap(find.text('Public'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('audience-followers')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();
    expect(find.text('The content is invalid.'), findsOneWidget);
    expect(find.textContaining('ApiError'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'My draft',
    );
    expect(find.text('Followers'), findsOneWidget);
    repo.error = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(CreatePostScreen), findsNothing);
    expect(result!.content, 'My draft');
    expect(repo.requests.last.visibility.name, 'followers');
  });

  testWidgets(
    'back and close ask before discarding and Cancel retains the draft',
    (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), 'Unsaved');
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard Post?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Unsaved',
      );
      await tester.tap(find.byTooltip('Close composer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(CreatePostScreen), findsNothing);
      expect(result, isNull);
      expect(repo.requests, isEmpty);
    },
  );

  testWidgets('back cannot discard while submission is pending', (
    tester,
  ) async {
    repo.gate = Completer<PostModel>();
    await open(tester);
    await tester.enterText(find.byType(TextField), 'Publishing');
    await tester.pump();
    await tester.tap(find.text('Post'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Discard Post?'), findsNothing);
    expect(find.byType(CreatePostScreen), findsOneWidget);
    repo.gate!.complete(PostModel.fromJson(postJson()));
    await tester.pumpAndSettle();
    expect(repo.requests, hasLength(1));
    expect(result!.id, '42');
  });

  testWidgets(
    'center Add publishes and refreshes the same feeds while retaining Home tab selection',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final feeds = Feeds();
      final account = home.AccountRepo();
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            theme: darkTheme,
            home: Root(
              createPostRepo: repo,
              postsRepo: feeds,
              homeAccountRepo: account,
              followRepo: home.PeopleRepo(account),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final explore = tester
          .widget<BlocBuilder<PostsCubit, PostsState>>(
            find.byKey(const ValueKey('home-feed-content')),
          )
          .bloc;
      await tester.tap(find.text('Following'));
      await tester.pumpAndSettle();
      final following = tester
          .widget<BlocBuilder<PostsCubit, PostsState>>(
            find.byKey(const ValueKey('home-feed-content')),
          )
          .bloc;
      final nav = tester.getRect(find.byType(BottomNavigationBar));
      await tester.tapAt(nav.center);
      await tester.pumpAndSettle();
      expect(find.byType(CreatePostScreen), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'A new post');
      await tester.pump();
      await tester.tap(find.text('Post'));
      await tester.pumpAndSettle();
      expect(find.text('Post published successfully'), findsOneWidget);
      expect(
        feeds.calls.where((feed) => feed == FeedType.explore),
        hasLength(2),
      );
      expect(
        feeds.calls.where((feed) => feed == FeedType.following),
        hasLength(2),
      );
      expect(tester.widget<HomeTabs>(find.byType(HomeTabs)).selectedIndex, 1);
      expect(
        tester
            .widget<BlocBuilder<PostsCubit, PostsState>>(
              find.byKey(const ValueKey('home-feed-content')),
            )
            .bloc,
        same(following),
      );
      await tester.tap(
        find.descendant(
          of: find.byType(HomeTabs),
          matching: find.text('For You'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BlocBuilder<PostsCubit, PostsState>>(
              find.byKey(const ValueKey('home-feed-content')),
            )
            .bloc,
        same(explore),
      );
      expect((following!.state as PostsLoaded).posts, isEmpty);
      expect((explore!.state as PostsLoaded).posts, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('short drafts stay visible above the keyboard', (tester) async {
    await open(tester);
    addTearDown(tester.view.resetViewInsets);
    await tester.enterText(find.byType(TextField), 'A trip');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(
      tester.getBottomLeft(find.byType(TextField)).dy,
      lessThanOrEqualTo(544),
    );
    expect(tester.takeException(), isNull);
  });
}
