import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/profile/screens/profile_screen.dart';
import 'package:travibe/features/stories/cubit/stories_cubit.dart';
import 'package:travibe/features/stories/cubit/story_upload_cubit.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/screens/story_viewer_screen.dart';
import 'package:travibe/features/stories/widgets/post_story_sheet.dart';
import 'package:travibe/features/stories/widgets/story_ring.dart';
import 'package:travibe/root.dart';

import '../home/home_experience_fixtures.dart';
import '../profile/fixtures.dart' as profile;
import 'story_owner_controls_test.dart' show OwnerRepo;
import 'story_publishing_test.dart' show groupJson, pageJson;

/// Stories feed whose content the test switches (published / deleted).
class _Feed extends OwnerRepo {
  List<Map<String, dynamic>> groups = [];
  int reads = 0;
  _Feed() {
    groupsHandler = (_) async {
      reads++;
      return StoriesPage.fromJson(pageJson(groups));
    };
    deleteHandler = (_) async => groups = [];
  }
}

Map<String, dynamic> _liveGroup(int userId, {bool seen = false}) {
  final json = groupJson(userId, storyId: 1);
  for (final story in json['stories'] as List) {
    story['expires_at'] = DateTime.now()
        .add(const Duration(hours: 2))
        .toIso8601String();
    story['has_seen'] = seen;
  }
  json['has_unseen'] = !seen;
  return json;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('profile-story-ring');
  });
  tearDown(() => PreferencesManager().clear());

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  final ring = find.byKey(const ValueKey('profile-story-ring'));

  testWidgets(
    'publish from Home → my profile shows the ring; delete → ring gone',
    (tester) async {
      phone(tester);
      final feed = _Feed();
      final account = AccountRepo();
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            theme: darkTheme,
            home: Root(
              postsRepo: EmptyPostsRepo(),
              homeAccountRepo: account,
              followRepo: PeopleRepo(account),
              profileRepo: profile.MemoryProfileRepo(),
              storiesRepo: feed,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      BottomNavigationBar bar() =>
          tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      bar().onTap!(4);
      await tester.pumpAndSettle();
      expect(ring, findsNothing);

      // A background upload started on Home finishes (Root's queue).
      feed.groups = [_liveGroup(7)];
      final uploads = tester
          .element(find.byType(BottomNavigationBar))
          .read<StoryUploadCubit>();
      // ignore: invalid_use_of_protected_member
      uploads.emit(const StoryUploadDone(null));
      await tester.pumpAndSettle();

      // Profile (no restart) and Home's row share the same source.
      expect(ring, findsOneWidget);
      expect(tester.widget<StoryRing>(ring).stories.map((s) => s.id), [1]);
      expect(
        find.byKey(const ValueKey('story-segments-7'), skipOffstage: false),
        findsOneWidget,
      );

      // "+" still adds a Story; the picture's sheet opens my Story.
      await tester.tap(find.byKey(const ValueKey('profile-add-story')));
      await tester.pumpAndSettle();
      expect(find.byType(PostStorySheet), findsOneWidget);
      await tester.tapAt(const Offset(10, 100));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-open-stories')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-view-story')));
      await tester.pumpAndSettle();
      expect(find.byType(StoryViewerScreen), findsOneWidget);
      expect(
        tester
            .widget<StoryViewerScreen>(find.byType(StoryViewerScreen))
            .initialAuthorId,
        7,
      );

      // The viewer confirms a delete (as after "Delete story" → Delete);
      // the server no longer returns the Story.
      feed.groups = [];
      tester
          .widget<StoryViewerScreen>(find.byType(StoryViewerScreen))
          .onDeleted!(1);
      Navigator.of(tester.element(find.byType(StoryViewerScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(StoryViewerScreen), findsNothing);
      expect(bar().currentIndex, 4);
      expect(ring, findsNothing);
      expect(
        find.byKey(const ValueKey('story-segments-7'), skipOffstage: false),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  group('another user', () {
    late FollowCubit follow;
    late BlockCubit block;
    late _Feed feed;
    late StoriesCubit stories;
    setUp(() {
      follow = FollowCubit();
      block = BlockCubit(follow: follow);
      feed = _Feed()..groups = [_liveGroup(8, seen: true)];
      stories = StoriesCubit(repo: feed, blocks: block);
    });
    // Each test closes `stories` itself (its expiry timer must stop first).
    tearDown(() async {
      await block.close();
      await follow.close();
    });

    Future<void> show(WidgetTester tester, {int userId = 8}) async {
      phone(tester);
      await stories.load();
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            theme: darkTheme,
            home: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: follow),
                BlocProvider.value(value: block),
                BlocProvider.value(value: stories),
              ],
              child: ProfileScreen(
                userId: userId,
                profileRepo: profile.MemoryProfileRepo()
                  ..result = profile.profile(id: userId),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a visible Story rings their picture and opens their Story', (
      tester,
    ) async {
      await show(tester);
      expect(ring, findsOneWidget);
      // All seen → the grey (seen) segment, like Home.
      expect(tester.widget<StoryRing>(ring).stories.single.hasSeen, isTrue);
      expect(find.byKey(const ValueKey('profile-add-story')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('profile-open-stories')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<StoryViewerScreen>(find.byType(StoryViewerScreen))
            .initialAuthorId,
        8,
      );
      // Expiry timers must stop before the binding's pending-timer check;
      // close() cancels the timer synchronously.
      unawaited(stories.close());
    });

    testWidgets('no Story and no picture → avatar is not tappable', (
      tester,
    ) async {
      await show(tester, userId: 9);
      expect(ring, findsNothing);
      expect(find.byKey(const ValueKey('profile-open-stories')), findsNothing);
      // Expiry timers must stop before the binding's pending-timer check;
      // close() cancels the timer synchronously.
      unawaited(stories.close());
    });

    testWidgets('pull-to-refresh also refreshes Stories', (tester) async {
      await show(tester);
      final before = feed.reads;
      feed.groups = [];
      unawaited(
        tester
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .onRefresh(),
      );
      await tester.pumpAndSettle();
      expect(feed.reads, before + 1);
      expect(ring, findsNothing);
      // Expiry timers must stop before the binding's pending-timer check;
      // close() cancels the timer synchronously.
      unawaited(stories.close());
    });
  });

  testWidgets('expired Stories drop out of the shared source on time', (
    tester,
  ) async {
    var clock = DateTime.now();
    final feed = _Feed();
    final group = _liveGroup(7);
    (group['stories'] as List).single['expires_at'] = clock
        .add(const Duration(minutes: 1))
        .toIso8601String();
    feed.groups = [group];
    final stories = StoriesCubit(repo: feed, now: () => clock);
    addTearDown(stories.close);
    await stories.load();
    expect(stories.groupOf(7), isNotNull);
    await tester.pump(const Duration(seconds: 30));
    expect(stories.groupOf(7), isNotNull);
    clock = clock.add(const Duration(minutes: 2));
    await tester.pump(const Duration(seconds: 31));
    expect(stories.groupOf(7), isNull);
    expect(stories.state.groups, isEmpty);
  });
}
