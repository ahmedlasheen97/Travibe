import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/navigation/app_cubits.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/user_profile_link.dart';
import 'package:travibe/features/home/screens/home_screen.dart';
import 'package:travibe/features/notifications/data/notification_model.dart';
import 'package:travibe/features/notifications/data/notification_targets.dart';
import 'package:travibe/features/notifications/screens/notification_navigation.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'package:travibe/features/profile/screens/open_shared_profile.dart';
import 'package:travibe/features/profile/screens/profile_screen.dart';
import 'package:travibe/features/stories/data/story_model.dart';
import 'package:travibe/features/stories/screens/story_viewer_screen.dart';
import 'package:travibe/root.dart';

import '../../helpers/fake_network_images.dart';
import '../home/home_experience_fixtures.dart';
import '../stories/fixtures.dart' show photoBytes;
import '../stories/story_owner_controls_test.dart' show OwnerRepo, viewerJson;
import '../stories/story_publishing_test.dart' show pageJson;
import '../stories/story_viewer_test.dart' show viewerGroup;
import 'fixtures.dart';

const _me = 7, _other = 23;

void main() {
  late MemoryProfileRepo others;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('profile-entry-points');
    others = MemoryProfileRepo()
      ..result = ProfileModel.fromJson({
        ...profileJson(id: _other),
        'is_me': false,
        'is_following': false,
      });
  });
  tearDown(() => PreferencesManager().clear());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// The real app shell, with the shared current user above it like MyApp.
  Future<void> showApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final mine = MemoryProfileRepo()
      ..result = ProfileModel.fromJson(profileJson(id: _me));
    final current = CurrentUserCubit(profileRepo: mine);
    addTearDown(current.close);
    await current.load();
    final account = AccountRepo();
    await tester.pumpWidget(
      BlocProvider.value(
        value: current,
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            theme: darkTheme,
            home: Root(
              postsRepo: EmptyPostsRepo(),
              homeAccountRepo: account,
              followRepo: PeopleRepo(account),
              profileRepo: mine,
              storiesRepo: OwnerRepo(),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  /// The app navigator's own context: above Root, like push-notification
  /// taps and deep links (and any route pushed without Root's providers).
  BuildContext aboveRoot(WidgetTester tester) =>
      tester.element(find.byType(Navigator).first);

  void expectFullProfile(WidgetTester tester) {
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.byTooltip('Profile options'), findsOneWidget, reason: '⋮');
    expect(find.text('Message'), findsOneWidget);
    expect(find.text('Follow'), findsOneWidget);
  }

  final entryPoints =
      <String, Future<void> Function(WidgetTester, MemoryProfileRepo)>{
        // Posts, comments, likes, follower lists, search, Buddies, chat.
        'in-app row (inside Root)': (tester, repo) => openUserProfile(
          tester.element(find.byType(HomeScreen)),
          _other,
          profileRepo: repo,
          postsRepo: EmptyProfilePostsRepo(),
        ),
        'a route pushed above Root': (tester, repo) => openUserProfile(
          aboveRoot(tester),
          _other,
          profileRepo: repo,
          postsRepo: EmptyProfilePostsRepo(),
        ),
        'deep link (travibe://users/{id})': (tester, repo) => openSharedProfile(
          aboveRoot(tester),
          _other,
          profileRepo: repo,
          postsRepo: EmptyProfilePostsRepo(),
        ),
        'notification (profile target)': (tester, repo) =>
            openNotificationDestination(
              aboveRoot(tester),
              InboxNotification.fromJson({
                'id': 'n1',
                'type': 'new_follower',
                'actor': {'id': _other, 'name': 'Traveler'},
                'data': <String, dynamic>{},
                'created_at': '2026-11-06T23:00:00Z',
              }),
              const NotificationContent(
                NotificationTarget(NotificationTargetKind.profile, _other),
              ),
              profiles: repo,
              posts: EmptyProfilePostsRepo(),
            ),
      };

  for (final entry in entryPoints.entries) {
    testWidgets('${entry.key}: profile has ⋮, Message and Follow', (
      tester,
    ) async {
      await withFakeNetworkImages(() async {
        await showApp(tester);
        expect(AppCubits.current, isNotNull);
        entry.value(tester, others).ignore();
        await settle(tester);
        expectFullProfile(tester);
      });
    });
  }

  testWidgets(
    'Story viewers sheet (viewer pushed without providers): profile has ⋮, Message and Follow',
    (tester) async {
      await withFakeNetworkImages(() async {
        await showApp(tester);
        final photo = MemoryImage(photoBytes());
        final repo = OwnerRepo()
          ..viewersHandler = (_) async =>
              StoryViewersPage.fromJson(pageJson([viewerJson(_other)]));
        Navigator.of(aboveRoot(tester))
            .push<void>(
              MaterialPageRoute(
                builder: (_) => StoryViewerScreen(
                  groups: [
                    viewerGroup(_me, [1]),
                  ],
                  initialAuthorId: _me,
                  currentUserId: _me,
                  repo: repo,
                  imageProvider: (_) => photo,
                  onOpenProfile: (context, id) => openUserProfile(
                    context,
                    id,
                    profileRepo: others,
                    postsRepo: EmptyProfilePostsRepo(),
                  ),
                ),
              ),
            )
            .ignore();
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('story-views')));
        await settle(tester);
        await tester.tap(
          find.byKey(const ValueKey('story-viewer-row-$_other')),
        );
        await settle(tester);
        expectFullProfile(tester);
      });
    },
  );

  test('every profile entry point goes through openUserProfile', () {
    final direct = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (file.path.endsWith('user_profile_link.dart')) continue;
      final source = file.readAsStringSync();
      // Another user's profile: ProfileScreen.open with a userId.
      final calls = RegExp(
        r'ProfileScreen\.open\(([^;]*?)\)',
      ).allMatches(source);
      for (final call in calls) {
        if (call.group(1)!.contains('userId')) direct.add(file.path);
      }
    }
    expect(direct, isEmpty);
  });
}
