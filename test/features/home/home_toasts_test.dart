import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/error_retry_view.dart';
import 'package:travibe/core/media/media_upload_service.dart';
import 'package:travibe/core/widgets/travibe_toast.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/features/home/data/posts_page_model.dart';
import 'package:travibe/features/home/screens/home_screen.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/widgets/story_entry.dart';
import 'package:travibe/root.dart';
import 'package:travibe/features/home/data/post_model.dart';
import '../../helpers/cursor_fixtures.dart';
import 'package:travibe/core/network/reconnect_monitor.dart';
import 'package:travibe/core/widgets/image_retry_signal.dart';
import 'package:travibe/features/chats/data/chat_reachability.dart';
import 'package:travibe/features/home/widgets/following_empty_state.dart';
import 'package:travibe/features/home/widgets/home_loading_skeleton.dart';
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
    if (offline) throw _offline;
    return super.getPosts(feed: feed, cursor: cursor, perPage: perPage);
  }
}

final _offline = ApiError(
  message: 'Connection to API server failed. Check your internet connection.',
  isConnectionError: true,
);

/// Stories that fail like the feed while [offline]; [groups] when online.
class OfflineStories extends StoriesRepo {
  bool offline = false;
  int calls = 0;
  List<Map<String, dynamic>> groups = [];

  @override
  Future<StoriesPage> getStories({int page = 1}) async {
    calls++;
    if (offline) throw _offline;
    return StoriesPage.fromJson({
      'data': groups,
      'meta': {'current_page': 1, 'last_page': 1, 'per_page': 15, 'total': 0},
      'links': {'next': null},
    });
  }
}

Map<String, dynamic> storyGroup(int userId) => {
  'user': {'id': userId, 'name': 'Friend $userId', 'avatar_url': null},
  'has_unseen': true,
  'stories': [
    {
      'id': userId * 10,
      'thumbnail_url': null,
      'created_at': null,
      'expires_at': '2099-10-22T10:00:00Z',
      'views_count': 0,
      'has_seen': false,
    },
  ],
};

void main() {
  final preferences = PreferencesManager();
  late OfflineFeeds feeds;
  late OfflineStories stories;
  late home.AccountRepo account;
  late home.PeopleRepo people;
  late bool? networkUp;
  late ReconnectMonitor monitor;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
    await preferences.init();
    await preferences.saveToken('token');
    feeds = OfflineFeeds();
    stories = OfflineStories();
    account = home.AccountRepo();
    people = home.PeopleRepo(account);
    networkUp = false;
    monitor = ReconnectMonitor(
      status: () async => networkUp,
      reachability: ChatReachability(),
    );
  });
  tearDown(() async {
    monitor.dispose();
    await preferences.clear();
  });

  Future<void> pumpRoot(
    WidgetTester tester, {
    MediaUploadService Function()? uploads,
  }) async {
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
            postsRepo: feeds,
            homeAccountRepo: account,
            followRepo: people,
            storiesRepo: stories,
            mediaUploads: uploads,
            homeReconnectMonitor: monitor,
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

  void expectNoInlineErrors() {
    expect(find.byType(ErrorRetryView), findsNothing);
    expect(find.text('Retry Stories'), findsNothing);
    expect(find.byKey(const ValueKey('stories-retry')), findsNothing);
    expect(find.text('Retry'), findsNothing);
    expect(find.textContaining('Check your internet'), findsNothing);
  }

  testWidgets('offline feed is empty under a No internet toast and recovers '
      'when the connection comes back', (tester) async {
    await pumpRoot(tester);
    expect(find.byKey(const ValueKey('home-offline-feed')), findsOneWidget);
    expectNoInlineErrors();
    expect(find.text('Post 10'), findsNothing);
    expect(find.text('No internet connection'), findsOneWidget);
    expect(toast(tester)!.variant, TravibeToastVariant.error);
    expect(toast(tester)!.actionLabel, 'Refresh');
    expect(monitor.isRunning, isTrue);

    // Still offline: the interface check alone does not refetch.
    final before = feeds.calls;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(feeds.calls, before);
    expect(find.text('No internet connection'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-offline-feed')), findsOneWidget);

    feeds.offline = false;
    networkUp = true;
    final images = ImageRetrySignal.instance.value;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('No internet connection'), findsNothing);
    expect(find.text('Post 10'), findsOneWidget);
    expect(ImageRetrySignal.instance.value, greaterThan(images));

    // Retries stop once Home is back.
    expect(monitor.isRunning, isFalse);
    final settled = feeds.calls;
    await tester.pump(const Duration(seconds: 30));
    expect(feeds.calls, settled);
  });

  testWidgets('while offline a probe retries every third check', (
    tester,
  ) async {
    networkUp = null; // unknown interface status
    await pumpRoot(tester);
    final before = feeds.calls;
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(feeds.calls, before + 1);
    expect(find.text('No internet connection'), findsOneWidget);
  });

  testWidgets('one toast for every offline section; stories row shows only '
      'You with +; Refresh retries everything', (tester) async {
    stories.offline = true;
    people.listError = _offline;
    account.error = _offline;
    await pumpRoot(tester);
    expectNoInlineErrors();
    expect(find.byType(TravibeToastView), findsOneWidget);
    expect(find.text('No internet connection'), findsOneWidget);
    // Stories row: just "You" with the add badge, nothing else.
    expect(find.byKey(const ValueKey('story-ring-you')), findsOneWidget);
    expect(find.byKey(const ValueKey('add-story-photo')), findsOneWidget);
    expect(find.byKey(const ValueKey('stories-more')), findsNothing);
    expect(find.byType(HomeStorySkeleton), findsNothing);
    // Following tab shows no inline error either.
    await tester.tap(find.text('Following').first);
    await tester.pumpAndSettle();
    expectNoInlineErrors();
    expect(find.byType(FollowingEmptyState), findsNothing);
    await tester.tap(find.text('For You').first);
    await tester.pumpAndSettle();

    final calls = (feeds.calls, stories.calls, account.calls, people.listCalls);
    feeds.offline = false;
    stories.offline = false;
    stories.groups = [storyGroup(5)];
    people.listError = null;
    account.error = null;
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(feeds.calls, greaterThan(calls.$1));
    expect(stories.calls, greaterThan(calls.$2));
    expect(account.calls, greaterThan(calls.$3));
    expect(people.listCalls, greaterThan(calls.$4));
    expect(find.text('No internet connection'), findsNothing);
    expect(find.text('Post 10'), findsOneWidget);
    expect(find.text('Friend 5'), findsOneWidget);
  });

  testWidgets('reconnect retries only the failed sections and keeps cached '
      'stories visible meanwhile', (tester) async {
    feeds.offline = false;
    stories.groups = [storyGroup(5)];
    await pumpRoot(tester);
    expect(find.text('Friend 5'), findsOneWidget);
    expect(find.text('No internet connection'), findsNothing);

    // Connection drops: a stories refresh fails but cached stories stay.
    stories.offline = true;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 450));
    await tester.pumpAndSettle();
    expect(find.text('Friend 5'), findsOneWidget);
    expectNoInlineErrors();
    expect(find.text('No internet connection'), findsOneWidget);

    final feedCalls = feeds.calls;
    final storyCalls = stories.calls;
    stories.offline = false;
    networkUp = true;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('No internet connection'), findsNothing);
    expect(stories.calls, greaterThan(storyCalls));
    expect(feeds.calls, feedCalls);
    expect(find.text('Friend 5'), findsOneWidget);
  });

  testWidgets('an image-only failure starts the reconnect monitor without a '
      'toast and retries the image when the connection returns', (
    tester,
  ) async {
    ImageRetrySignal.instance.reset();
    addTearDown(ImageRetrySignal.instance.reset);
    feeds = _ImageFeeds();
    await pumpRoot(tester);
    // Let the missing image fail to load.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(ImageRetrySignal.instance.failedCount.value, 1);
    expect(monitor.isRunning, isTrue);
    expect(find.byType(TravibeToastView), findsNothing);

    // Still offline: no image retry yet.
    final before = ImageRetrySignal.instance.value;
    await tester.pump(const Duration(seconds: 5));
    expect(ImageRetrySignal.instance.value, before);

    networkUp = true;
    await tester.pump(const Duration(seconds: 5));
    expect(ImageRetrySignal.instance.value, before + 1);
    expect(find.byType(TravibeToastView), findsNothing);
  });

  testWidgets('the monitor stops once failed images are resolved', (
    tester,
  ) async {
    ImageRetrySignal.instance.reset();
    addTearDown(ImageRetrySignal.instance.reset);
    feeds.offline = false;
    await pumpRoot(tester);
    expect(monitor.isRunning, isFalse);
    final image = Object();
    ImageRetrySignal.instance.reportFailed(image);
    await tester.pump();
    expect(monitor.isRunning, isTrue);
    expect(find.byType(TravibeToastView), findsNothing);
    ImageRetrySignal.instance.reportResolved(image);
    await tester.pump();
    expect(monitor.isRunning, isFalse);
  });

  testWidgets('non-connection failures use the same toast with generic copy', (
    tester,
  ) async {
    feeds = _ServerErrorFeeds();
    await pumpRoot(tester);
    expectNoInlineErrors();
    expect(find.text('No internet connection'), findsNothing);
    expect(find.text(HomeErrorToast.failureMessage), findsOneWidget);
    expect(toast(tester)!.actionLabel, 'Refresh');
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

/// Online feed with one post whose image cannot load.
class _ImageFeeds extends OfflineFeeds {
  @override
  Future<PostsPageModel> getPosts({
    FeedType feed = FeedType.explore,
    String? cursor,
    int perPage = 15,
  }) async {
    calls++;
    return PostsPageModel(
      pagination: fixtureMeta(current: 1, last: 1),
      posts: feed == FeedType.explore
          ? [
              PostModel.fromJson({
                'id': 30,
                'type': 'image',
                'user_id': 3,
                'user': {'id': 3, 'name': 'Author 3', 'username': 'a3'},
                'content': 'Photo post',
                'visibility': 'public',
                'media': [
                  {'id': 1, 'url': 'assets/images/missing_post_image.png'},
                ],
              }),
            ]
          : [],
      currentPage: 1,
      lastPage: 1,
      total: 1,
    );
  }
}
