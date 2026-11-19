import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/home/screens/home_screen.dart';
import 'package:travibe/features/home/widgets/home_user_avatar.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'package:travibe/features/stories/data/stories_repo.dart';
import 'package:travibe/features/stories/data/story_model.dart';

import '../../helpers/fake_network_images.dart';
import '../profile/fixtures.dart' show MemoryProfileRepo, profileJson;
import 'home_experience_fixtures.dart' as fixture;
import 'home_responsive_ui_test.dart' show ResponsivePosts, ResponsiveSearch;

const _photo = 'https://example.invalid/me.png';
const _newPhoto = 'https://example.invalid/me-2.png';

ProfileModel me({int id = 1, String? avatar = _photo}) =>
    ProfileModel.fromJson({...profileJson(id: id), 'avatar_url': avatar});

class _NoStories extends StoriesRepo {
  @override
  Future<StoriesPage> getStories({int page = 1}) async => StoriesPage.fromJson({
    'data': [],
    'meta': {'current_page': 1, 'last_page': 1, 'per_page': 15, 'total': 0},
    'links': {'first': null, 'last': null, 'next': null, 'prev': null},
  });
}

void main() {
  final session = PreferencesManager();
  late fixture.AccountRepo account;
  late MemoryProfileRepo profiles;
  late CurrentUserCubit currentUser;
  late FollowCubit follow;
  late BlockCubit block;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await session.init();
    await session.saveToken('you-avatar-test');
    // The Home account (GET /user) has no picture, like the reported bug.
    account = fixture.AccountRepo()..followingCount = 2;
    profiles = MemoryProfileRepo()
      ..result = me()
      ..hold = true;
    currentUser = CurrentUserCubit(profileRepo: profiles);
    follow = FollowCubit(repo: fixture.PeopleRepo(account));
    block = BlockCubit(follow: follow);
  });
  tearDown(() async {
    await block.close();
    await follow.close();
    await currentUser.close();
    await session.clear();
  });

  Future<void> show(WidgetTester tester) async {
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
            body: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: currentUser),
                BlocProvider.value(value: follow),
                BlocProvider.value(value: block),
              ],
              child: HomeScreen(
                postsRepo: ResponsivePosts(),
                accountRepo: account,
                storiesRepo: _NoStories(),
                searchRepo: ResponsiveSearch(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  String? you(WidgetTester tester) => tester
      .widget<HomeUserAvatar>(find.byKey(const ValueKey('story-avatar-you')))
      .url;

  testWidgets('"You" shows my picture once the current profile loads, and '
      'follows picture changes', (tester) async {
    await withFakeNetworkImages(() async {
      await show(tester);
      // Home itself started the current-user load; nothing to show yet.
      expect(profiles.reads, hasLength(1));
      expect(you(tester), isNull);

      profiles.reads.single.result.complete(me());
      await tester.pump();
      await tester.pump();
      expect(you(tester), _photo);

      // A new picture (e.g. cached from the Profile tab) shows right away.
      currentUser.cacheProfile(
        me(avatar: _newPhoto),
        expectedSession: session.sessionRevision,
      );
      await tester.pump();
      await tester.pump();
      expect(you(tester), _newPhoto);
    });
  });

  testWidgets('"You" still shows my picture when the Home account fails', (
    tester,
  ) async {
    await withFakeNetworkImages(() async {
      account.error = ApiError(message: 'Unable to load your account.');
      profiles.hold = false;
      await currentUser.load();
      await show(tester);
      await tester.pump();
      expect(you(tester), _photo);
    });
  });

  testWidgets('signing out clears my picture from "You"', (tester) async {
    await withFakeNetworkImages(() async {
      profiles.hold = false;
      await currentUser.load();
      await show(tester);
      expect(you(tester), _photo);
      await session.clear();
      await tester.pump();
      await tester.pump();
      expect(you(tester), isNull);
    });
  });
}
