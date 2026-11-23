import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/home/screens/home_screen.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'package:travibe/features/profile/screens/profile_screen.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/screens/story_viewer_screen.dart';
import 'package:travibe/features/stories/widgets/open_story_viewer.dart';
import 'package:travibe/root.dart';

import '../../helpers/fake_network_images.dart';
import '../home/home_experience_fixtures.dart';
import '../profile/fixtures.dart' as fx;
import 'story_owner_controls_test.dart' show OwnerRepo;
import 'story_publishing_test.dart' show groupJson, pageJson;

/// Home's account fixture is user 1; my profile is the same user.
const _me = 1;

ProfileModel _profile(int id) => ProfileModel.fromJson({
  ...fx.profileJson(id: id),
  'avatar_url': 'https://img.travibe.test/$id.png',
});

class _Feed extends OwnerRepo {
  _Feed(List<Map<String, dynamic>> groups) {
    groupsHandler = (_) async => StoriesPage.fromJson(pageJson(groups));
  }
}

/// What a viewer was opened with, comparable across entry points.
typedef _Setup = ({
  String authors,
  String stories,
  int start,
  int? me,
  Object? repo,
  Object? likes,
});

_Setup _setupOf(WidgetTester tester) {
  final viewer = tester.widget<StoryViewerScreen>(
    find.byType(StoryViewerScreen),
  );
  return (
    authors: '${[for (final g in viewer.groups) g.user.id]}',
    stories:
        '${[
          for (final g in viewer.groups) [for (final s in g.stories) s.id],
        ]}',
    start: viewer.initialAuthorId,
    me: viewer.currentUserId,
    repo: viewer.repo,
    likes: viewer.likes,
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _closeViewer(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator).first).pop();
  await _settle(tester);
  expect(find.byType(StoryViewerScreen), findsNothing);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('story-entry-points');
  });
  tearDown(() => PreferencesManager().clear());

  test('play order puts my group first, then the source order', () {
    final groups = [
      for (final id in [8, _me, 9]) StoryGroup.fromJson(groupJson(id)),
    ];
    expect(storyPlayOrder(groups, _me).map((g) => g.user.id), [_me, 8, 9]);
    expect(storyPlayOrder(groups, null).map((g) => g.user.id), [8, _me, 9]);
  });

  /// Like MyApp: a loaded shared current user above the app.
  Future<void> showRoot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final account = AccountRepo();
    final profiles = fx.MemoryProfileRepo()..result = _profile(_me);
    final currentUser = CurrentUserCubit(profileRepo: profiles);
    addTearDown(currentUser.close);
    await currentUser.load();
    await tester.pumpWidget(
      BlocProvider.value(
        value: currentUser,
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            theme: darkTheme,
            home: Root(
              postsRepo: EmptyPostsRepo(),
              homeAccountRepo: account,
              followRepo: PeopleRepo(account),
              profileRepo: profiles,
              // Backend order: someone else first; the row still puts me first.
              storiesRepo: _Feed([groupJson(8), groupJson(_me), groupJson(9)]),
            ),
          ),
        ),
      ),
    );
    await _settle(tester);
  }

  void tab(WidgetTester tester, int index) => tester
      .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
      .onTap!(index);

  testWidgets('my Stories: Home "You" and Profile open the same viewer setup', (
    tester,
  ) async {
    await withFakeNetworkImages(() async {
      await showRoot(tester);

      await tester.tap(find.byKey(const ValueKey('your-story-bubble')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('view-my-story')));
      await _settle(tester);
      final fromHome = _setupOf(tester);
      await _closeViewer(tester);

      tab(tester, 4);
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('profile-avatar')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('view-my-story')));
      await _settle(tester);
      final fromProfile = _setupOf(tester);

      expect(fromHome.authors, '[$_me, 8, 9]');
      expect(fromHome.start, _me);
      expect(fromHome.me, _me);
      expect(fromHome.likes, isNotNull);
      expect(fromProfile, fromHome);
      await _closeViewer(tester);
    });
  });

  testWidgets(
    "another user's Stories: Home row and their Profile open the same viewer setup",
    (tester) async {
      await withFakeNetworkImages(() async {
        await showRoot(tester);

        await tester.tap(find.byKey(const ValueKey('story-author-8')));
        await _settle(tester);
        final fromHome = _setupOf(tester);
        await _closeViewer(tester);

        ProfileScreen.open(
          tester.element(find.byType(HomeScreen)),
          userId: 8,
          profileRepo: fx.MemoryProfileRepo()..result = _profile(8),
        ).ignore();
        await _settle(tester);
        await tester.tap(find.byKey(const ValueKey('profile-open-stories')));
        await _settle(tester);
        final fromProfile = _setupOf(tester);

        expect(fromHome.authors, '[$_me, 8, 9]');
        expect(fromHome.start, 8);
        expect(fromHome.me, _me);
        expect(fromProfile, fromHome);
        await _closeViewer(tester);
      });
    },
  );
}
