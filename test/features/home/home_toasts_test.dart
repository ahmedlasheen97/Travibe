import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/error_retry_view.dart';
import 'package:travibe/core/widgets/travibe_toast.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/features/home/data/posts_page_model.dart';
import 'package:travibe/features/home/screens/home_screen.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/widgets/story_entry.dart';
import 'package:travibe/root.dart';
import 'home_experience_fixtures.dart' as home;
import 'own_post_menu_test.dart' show MenuFeeds;

/// Explore feed that fails like Dio's connectionError while [offline].
class OfflineFeeds extends MenuFeeds {
  bool offline = true;
  int calls = 0;

  @override
  Future<PostsPageModel> getPosts({
    FeedType feed = FeedType.explore,
    String? cursor,
    int perPage = 15,
  }) async {
    calls++;
    if (offline) {
      throw ApiError(
        message:
            'Connection to API server failed. Check your internet connection.',
        isConnectionError: true,
      );
    }
    return super.getPosts(feed: feed, cursor: cursor, perPage: perPage);
  }
}

void main() {
  final preferences = PreferencesManager();
  late OfflineFeeds feeds;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
    await preferences.init();
    await preferences.saveToken('token');
    feeds = OfflineFeeds();
  });
  tearDown(() => preferences.clear());

  Future<void> pumpRoot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final account = home.AccountRepo();
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: Root(
            postsRepo: feeds,
            homeAccountRepo: account,
            followRepo: home.PeopleRepo(account),
            storiesRepo: _Stories(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  TravibeToastData? toast(WidgetTester tester) {
    final view = find.byType(TravibeToastView);
    return view.evaluate().isEmpty
        ? null
        : tester.widget<TravibeToastView>(view).data;
  }

  testWidgets('offline feed is empty under a No internet toast and recovers '
      'quietly when the connection returns', (tester) async {
    await pumpRoot(tester);
    expect(find.byKey(const ValueKey('home-offline-feed')), findsOneWidget);
    expect(find.byType(ErrorRetryView), findsNothing);
    expect(find.text('Post 10'), findsNothing);
    expect(find.text('No internet connection'), findsOneWidget);
    expect(toast(tester)!.variant, TravibeToastVariant.error);
    expect(toast(tester)!.actionLabel, 'Refresh');

    // Still offline: a quiet retry keeps the empty feed and the toast.
    final before = feeds.calls;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(feeds.calls, before + 1);
    expect(find.text('No internet connection'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-offline-feed')), findsOneWidget);

    feeds.offline = false;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('No internet connection'), findsNothing);
    expect(find.text('Post 10'), findsOneWidget);

    // Retries stop once the feed is back.
    final settled = feeds.calls;
    await tester.pump(const Duration(seconds: 15));
    expect(feeds.calls, settled);
  });

  testWidgets('Refresh retries the feed', (tester) async {
    await pumpRoot(tester);
    final before = feeds.calls;
    feeds.offline = false;
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(feeds.calls, before + 1);
    expect(find.text('No internet connection'), findsNothing);
    expect(find.text('Post 10'), findsOneWidget);
  });

  testWidgets('non-connection failures keep the inline retry view', (
    tester,
  ) async {
    feeds = _ServerErrorFeeds();
    await pumpRoot(tester);
    expect(find.byType(ErrorRetryView), findsOneWidget);
    expect(find.text('No internet connection'), findsNothing);
  });

  testWidgets('publishing a story from Home shows the success toast', (
    tester,
  ) async {
    feeds.offline = false;
    await pumpRoot(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.widget<StoryEntry>(find.byType(StoryEntry)).onPublished!();
    await tester.pumpAndSettle();
    expect(find.text('Story published successfully'), findsOneWidget);
    expect(toast(tester)!.variant, TravibeToastVariant.success);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Story published successfully'), findsNothing);
  });
}

class _Stories extends StoriesRepo {
  @override
  Future<StoriesPage> getStories({int page = 1}) async => StoriesPage.fromJson({
    'data': [],
    'meta': {'current_page': 1, 'last_page': 1, 'per_page': 15, 'total': 0},
    'links': {'next': null},
  });
}

class _ServerErrorFeeds extends OfflineFeeds {
  @override
  Future<PostsPageModel> getPosts({
    FeedType feed = FeedType.explore,
    String? cursor,
    int perPage = 15,
  }) async {
    calls++;
    throw ApiError(message: 'Server error', statusCode: 500);
  }
}
