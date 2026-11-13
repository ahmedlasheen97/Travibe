import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/screens/follow_users_screen.dart';
import 'package:travibe/features/follow_requests/cubit/incoming_requests_cubit.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'package:travibe/features/profile/screens/profile_screen.dart';
import 'package:travibe/features/profile/widgets/private_profile_locked.dart';
import 'package:travibe/features/profile/widgets/profile_tabs.dart';

import '../profile/fixtures.dart';
import '../profile/other_user_profile_test.dart' show Blocks, Follows;
import 'follow_requests_fakes.dart';

void main() {
  late MemoryProfileRepo profiles;
  late FollowCubit follow;
  late BlockCubit block;
  late FakeFollowRequestsRepo requests;
  late CountingCurrentUser current;
  late IncomingRequestsCubit incoming;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('private-profile-test');
    profiles = MemoryProfileRepo();
    follow = FollowCubit(repo: Follows());
    block = BlockCubit(follow: follow, repo: Blocks());
    requests = FakeFollowRequestsRepo(
      pages: {
        1: requestsPage([23]),
      },
    );
    current = CountingCurrentUser();
    incoming = IncomingRequestsCubit(
      repo: requests,
      follow: follow,
      currentUser: () => current,
    );
  });
  tearDown(() async {
    await incoming.close();
    await current.close();
    await block.close();
    await follow.close();
  });

  void profile({bool locked = false, bool requested = false}) =>
      profiles.result = ProfileModel.fromJson({
        ...profileJson(id: 23),
        'is_me': false,
        'is_following': false,
        'follows_you': false,
        'is_private': locked,
        'follow_requested': requested,
        'can_view_content': !locked,
      });

  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: ThemeData.dark(),
          home: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: follow),
              BlocProvider.value(value: block),
              BlocProvider.value(value: incoming),
            ],
            child: ProfileScreen(
              userId: 23,
              profileRepo: profiles,
              postsRepo: EmptyProfilePostsRepo(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('locked private profile keeps header but hides posts and lists', (
    tester,
  ) async {
    profile(locked: true, requested: true);
    await show(tester);
    expect(find.byType(PrivateProfileLocked), findsOneWidget);
    expect(find.text('This account is private'), findsOneWidget);
    expect(find.text('Follow this account to see their posts'), findsOneWidget);
    expect(find.byType(ProfileTabs), findsNothing);
    expect(find.text('No posts yet'), findsNothing);
    // Header, counts and the Requested button stay.
    expect(find.text('Mona Hassan'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Requested'), findsOneWidget);
    // Followers/following lists are 403 for a locked account.
    await tester.tap(find.text('12'));
    await tester.pumpAndSettle();
    expect(find.byType(FollowUsersScreen), findsNothing);
  });

  testWidgets('public profile shows tabs and no locked state', (tester) async {
    profile();
    await show(tester);
    expect(find.byType(PrivateProfileLocked), findsNothing);
    expect(find.byType(ProfileTabs), findsOneWidget);
    expect(find.text('Follow'), findsOneWidget);
  });

  testWidgets(
    'request card appears for a pending requester and accept hides it',
    (tester) async {
      profile();
      await incoming.sync();
      await show(tester);
      expect(find.text('Requested to follow you.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('accept-request-23')));
      await tester.pumpAndSettle();
      expect(requests.accepted, ['23']);
      expect(find.text('Requested to follow you.'), findsNothing);
      expect(current.deltas, [1]);
      expect(follow.state.followsYou['23'], isTrue);
    },
  );

  testWidgets('decline hides the card; no card without a request', (
    tester,
  ) async {
    profile();
    await show(tester);
    expect(find.text('Requested to follow you.'), findsNothing);
    await incoming.sync();
    await tester.pumpAndSettle();
    expect(find.text('Requested to follow you.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('decline-request-23')));
    await tester.pumpAndSettle();
    expect(requests.declined, ['23']);
    expect(find.text('Requested to follow you.'), findsNothing);
    expect(current.deltas, isEmpty);
  });
}
