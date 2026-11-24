import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'package:travibe/features/profile/screens/profile_screen.dart';
import 'package:travibe/features/stories/cubit/stories_cubit.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/screens/story_viewer_screen.dart';
import 'package:travibe/features/stories/widgets/story_ring.dart';

import '../profile/fixtures.dart' as profile;
import 'story_owner_controls_test.dart' show OwnerRepo;
import 'story_publishing_test.dart'
    show StoryAdapter, groupJson, pageJson, repository, response;

Map<String, dynamic> _story(int id, {bool seen = false}) => {
  'id': id,
  'thumbnail_url': null,
  'created_at': null,
  'expires_at': DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
  'views_count': 0,
  'has_seen': seen,
};

const _author = StoryAuthor(id: 8, name: 'Mona Hassan', username: 'mona');

/// Home's bar (`GET /stories`) and one user's list
/// (`GET /users/{user}/stories`, newest first) under the test's control.
class _Stories extends OwnerRepo {
  List<Map<String, dynamic>> bar = [];

  /// Newest first, as the API sends it. Null → `404`.
  List<Map<String, dynamic>>? user = [];
  Object? userError;
  final userReads = <int>[];

  _Stories() {
    groupsHandler = (_) async => StoriesPage.fromJson(pageJson(bar));
  }

  @override
  Future<StoryGroup?> getUserStories(StoryAuthor author) async {
    userReads.add(author.id);
    if (userError != null) throw userError!;
    final rows = user;
    if (rows == null || rows.isEmpty) return null;
    return StoryGroup.ofNewestFirst(author, rows.map(StorySummary.fromJson));
  }
}

ProfileModel _profile(int id, {bool locked = false}) => ProfileModel.fromJson({
  ...profile.profileJson(id: id),
  'is_following': false,
  'is_private': locked,
  'can_view_content': !locked,
});

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('user-stories');
  });
  tearDown(() => PreferencesManager().clear());

  final ring = find.byKey(const ValueKey('profile-story-ring'));
  List<int> ringIds(WidgetTester tester) =>
      tester.widget<StoryRing>(ring).stories.map((s) => s.id).toList();
  List<bool> ringSeen(WidgetTester tester) =>
      tester.widget<StoryRing>(ring).stories.map((s) => s.hasSeen).toList();

  group('StoriesRepo.getUserStories', () {
    test('GET users/{id}/stories, played oldest → newest', () async {
      final adapter = StoryAdapter()
        ..handler = (_) async => response({
          'data': [_story(3), _story(2, seen: true), _story(1)],
        });
      final group = await repository(adapter).getUserStories(_author);
      expect(adapter.requests.single.method, 'GET');
      expect(adapter.requests.single.path, 'users/8/stories');
      expect(
        adapter.requests.single.extra['sessionRevision'],
        PreferencesManager().sessionRevision,
      );
      expect(group!.user.id, 8);
      expect(group.stories.map((s) => s.id), [1, 2, 3]);
      expect(group.hasUnseen, isTrue);
    });

    test('an empty list (none visible or a block) → null', () async {
      final adapter = StoryAdapter()
        ..handler = (_) async => response({'data': []});
      expect(await repository(adapter).getUserStories(_author), isNull);
    });

    for (final status in [403, 404]) {
      test('$status → null', () async {
        final adapter = StoryAdapter()
          ..handler = (_) async => response({'message': 'No'}, status: status);
        expect(await repository(adapter).getUserStories(_author), isNull);
      });
    }

    test('other failures throw ApiError', () async {
      final adapter = StoryAdapter()
        ..handler = (_) async => response({'message': 'Boom'}, status: 500);
      await expectLater(
        repository(adapter).getUserStories(_author),
        throwsA(isA<ApiError>()),
      );
      adapter.handler = (_) async => response({'data': null});
      await expectLater(
        repository(adapter).getUserStories(_author),
        throwsA(isA<ApiError>()),
      );
    });
  });

  test('Home bar groups also play oldest → newest', () {
    final json = groupJson(8)..['stories'] = [_story(3), _story(2), _story(1)];
    expect(StoryGroup.fromJson(json).stories.map((s) => s.id), [1, 2, 3]);
  });

  test('confirmed views grey a profile group and the bar group', () async {
    final repo = _Stories()
      ..bar = [
        groupJson(8)..['stories'] = [_story(2), _story(1)],
      ];
    final stories = StoriesCubit(repo: repo);
    addTearDown(stories.close);
    await stories.load();
    final fetched = StoryGroup.ofNewestFirst(_author, [
      StorySummary.fromJson(_story(2)),
      StorySummary.fromJson(_story(1)),
    ]);
    stories
      ..confirmedView(1, 1)
      ..confirmedView(2, 1);
    expect(stories.reconcileGroup(fetched)!.hasUnseen, isFalse);
    expect(stories.groupOf(8)!.hasUnseen, isFalse);
    stories.confirmedDelete(1);
    expect(stories.reconcileGroup(fetched)!.stories.map((s) => s.id), [2]);
  });

  group('another user I don\'t follow', () {
    late FollowCubit follow;
    late BlockCubit block;
    late _Stories repo;
    late StoriesCubit stories;
    setUp(() => repo = _Stories());
    tearDown(() async {
      await block.close();
      await follow.close();
    });

    Future<void> show(
      WidgetTester tester, {
      int userId = 8,
      bool locked = false,
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      // Created inside the test's zone so their stream events reach widgets.
      follow = FollowCubit();
      block = BlockCubit(follow: follow);
      stories = StoriesCubit(repo: repo, blocks: block);
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
                  ..result = _profile(userId, locked: locked),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Stops the Stories expiry timers before the pending-timer check.
    Future<void> done(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      unawaited(stories.close());
      await tester.pump();
    }

    testWidgets(
      'a public user outside my bar gets the ring; their Stories play alone, '
      'oldest → newest',
      (tester) async {
        repo.user = [_story(3), _story(2), _story(1)];
        await show(tester);
        expect(repo.userReads, [8]);
        expect(ring, findsOneWidget);
        expect(ringIds(tester), [1, 2, 3]);
        final painter =
            tester
                    .widget<CustomPaint>(
                      find.descendant(
                        of: ring,
                        matching: find.byType(CustomPaint),
                      ),
                    )
                    .foregroundPainter!
                as StoryRingPainter;
        expect(painter.colors, List.filled(3, DarkColors.primaryColor));

        await tester.tap(find.byKey(const ValueKey('profile-open-stories')));
        await tester.pumpAndSettle();
        final viewer = tester.widget<StoryViewerScreen>(
          find.byType(StoryViewerScreen),
        );
        expect(viewer.initialAuthorId, 8);
        expect(viewer.groups.map((g) => g.user.id), [8]);
        expect(viewer.groups.single.stories.map((s) => s.id), [1, 2, 3]);
        await done(tester);
      },
    );

    testWidgets('viewing turns the profile ring grey and refetches on close', (
      tester,
    ) async {
      repo.user = [_story(1)];
      await show(tester);
      expect(ringSeen(tester), [false]);
      await tester.tap(find.byKey(const ValueKey('profile-open-stories')));
      await tester.pumpAndSettle();
      final viewer = tester.widget<StoryViewerScreen>(
        find.byType(StoryViewerScreen),
      );
      // The viewer confirms a view (POST /view, then the detail count) only
      // after the photo decodes; fire the confirmation it would send.
      viewer.onViewed!(1, 1);
      await tester.pumpAndSettle();
      expect(
        stories
            .reconcileGroup(
              StoryGroup.ofNewestFirst(_author, [
                StorySummary.fromJson(_story(1)),
              ]),
            )!
            .hasUnseen,
        isFalse,
      );
      final reads = repo.userReads.length;
      repo.user = [_story(1, seen: true)];
      Navigator.of(tester.element(find.byType(StoryViewerScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(StoryViewerScreen), findsNothing);
      expect(ringSeen(tester), [true]);
      expect(repo.userReads.length, greaterThan(reads));
      await done(tester);
    });

    testWidgets('a confirmed view greys the ring before any refetch', (
      tester,
    ) async {
      repo.user = [_story(2), _story(1)];
      await show(tester);
      stories.confirmedView(1, 1);
      await tester.pumpAndSettle();
      expect(ringSeen(tester), [true, false]);
      await done(tester);
    });

    testWidgets('a private profile I can\'t see → no request, no ring', (
      tester,
    ) async {
      repo.user = [_story(1)];
      await show(tester, locked: true);
      expect(repo.userReads, isEmpty);
      expect(ring, findsNothing);
      await done(tester);
    });

    for (final (name, setUpRepo) in <(String, void Function(_Stories))>[
      ('no Stories', (r) => r.user = []),
      ('404', (r) => r.user = null),
      ('an error', (r) => r.userError = ApiError(message: 'Unable to load')),
    ]) {
      testWidgets('$name → no ring and no error text', (tester) async {
        setUpRepo(repo);
        await show(tester);
        expect(repo.userReads, [8]);
        expect(ring, findsNothing);
        expect(
          find.byKey(const ValueKey('profile-open-stories')),
          findsNothing,
        );
        expect(find.textContaining('Unable'), findsNothing);
        await done(tester);
      });
    }

    testWidgets('pull-to-refresh refetches the ring', (tester) async {
      await show(tester);
      expect(ring, findsNothing);
      repo.user = [_story(1)];
      unawaited(
        tester
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .onRefresh(),
      );
      await tester.pumpAndSettle();
      expect(repo.userReads, [8, 8]);
      expect(ring, findsOneWidget);
      await done(tester);
    });

    testWidgets('returning to the profile refetches the ring', (tester) async {
      repo.user = [_story(1)];
      await show(tester);
      expect(ring, findsOneWidget);
      final navigator = Navigator.of(tester.element(ring));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const Scaffold()),
        ),
      );
      await tester.pumpAndSettle();
      repo.user = [];
      navigator.pop();
      await tester.pumpAndSettle();
      expect(repo.userReads, [8, 8]);
      expect(ring, findsNothing);
      await done(tester);
    });

    testWidgets('someone in my bar still opens with Home\'s order', (
      tester,
    ) async {
      repo.bar = [
        groupJson(8)..['stories'] = [_story(1)],
        groupJson(9)..['stories'] = [_story(5)],
      ];
      repo.user = [_story(1)];
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('profile-open-stories')));
      await tester.pumpAndSettle();
      final viewer = tester.widget<StoryViewerScreen>(
        find.byType(StoryViewerScreen),
      );
      expect(viewer.groups.map((g) => g.user.id), [8, 9]);
      await done(tester);
    });
  });
}
