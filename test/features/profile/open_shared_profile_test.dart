import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/block/data/block_repo.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'package:travibe/features/profile/screens/open_shared_profile.dart';
import 'package:travibe/features/profile/screens/profile_screen.dart';
import 'fixtures.dart';

class _Blocks extends BlockRepo {
  @override
  Future<PublicUserModel> setBlocked(String userId, bool value) async =>
      PublicUserModel.fromJson({
        'id': int.parse(userId),
        'name': 'Traveler',
        'is_blocked': value,
      });
}

void main() {
  late MemoryProfileRepo profiles;
  late FollowCubit follow;
  late BlockCubit block;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('shared-profile-test');
    profiles = MemoryProfileRepo()
      ..result = ProfileModel.fromJson({
        ...profileJson(id: 23),
        'is_me': false,
      });
    follow = FollowCubit(repo: FollowRepo());
    block = BlockCubit(follow: follow, repo: _Blocks());
  });
  tearDown(() async {
    await block.close();
    await follow.close();
    await PreferencesManager().clearSession();
  });

  Future<BuildContext> host(
    WidgetTester tester, {
    CurrentUserCubit? current,
  }) async {
    late BuildContext captured;
    Widget app = MultiBlocProvider(
      providers: [
        BlocProvider.value(value: follow),
        BlocProvider.value(value: block),
      ],
      child: Scaffold(
        body: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      ),
    );
    if (current != null) {
      app = BlocProvider.value(value: current, child: app);
    }
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(theme: ThemeData.dark(), home: app),
      ),
    );
    return captured;
  }

  Future<int> open(WidgetTester tester, BuildContext context, int id) async {
    var mine = 0;
    // Completes only when a pushed profile route pops; don't await it.
    unawaited(
      openSharedProfile(
        context,
        id,
        showMyProfile: () => mine++,
        profileRepo: profiles,
        postsRepo: EmptyProfilePostsRepo(),
      ),
    );
    await tester.pumpAndSettle();
    return mine;
  }

  testWidgets('a visible profile opens the public ProfileScreen', (
    tester,
  ) async {
    final context = await host(tester);
    expect(await open(tester, context, 23), 0);
    expect(profiles.reads.map((r) => r.userId), contains(23));
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.text('Mona Hassan'), findsWidgets);
    expect(find.text(sharedProfileUnavailable), findsNothing);
  });

  testWidgets('data:null (blocked by the backend) is unavailable', (
    tester,
  ) async {
    profiles.result = null;
    final context = await host(tester);
    await open(tester, context, 23);
    expect(find.byType(ProfileScreen), findsNothing);
    expect(find.text(sharedProfileUnavailable), findsOneWidget);
  });

  testWidgets('404 is unavailable', (tester) async {
    profiles.error = ApiError(message: 'Not found.', statusCode: 404);
    final context = await host(tester);
    await open(tester, context, 999);
    expect(find.byType(ProfileScreen), findsNothing);
    expect(find.text(sharedProfileUnavailable), findsOneWidget);
  });

  testWidgets('a user the viewer blocked is unavailable', (tester) async {
    await block.setBlocked('23', true);
    final context = await host(tester);
    await open(tester, context, 23);
    expect(find.byType(ProfileScreen), findsNothing);
    expect(find.text(sharedProfileUnavailable), findsOneWidget);
  });

  testWidgets('my own id opens the Profile tab without a fetch', (
    tester,
  ) async {
    final mineRepo = MemoryProfileRepo()..result = profile(id: 23);
    final current = CurrentUserCubit(profileRepo: mineRepo);
    addTearDown(current.close);
    await current.load();
    final context = await host(tester, current: current);
    final before = profiles.reads.length;
    expect(await open(tester, context, 23), 1);
    expect(profiles.reads.length, before);
    expect(find.byType(ProfileScreen), findsNothing);
  });

  testWidgets('is_me from users/{id} also opens the Profile tab', (
    tester,
  ) async {
    profiles.result = ProfileModel.fromJson({
      ...profileJson(id: 23),
      'is_me': true,
    });
    final context = await host(tester);
    expect(await open(tester, context, 23), 1);
    expect(find.byType(ProfileScreen), findsNothing);
    expect(find.text(sharedProfileUnavailable), findsNothing);
  });

  testWidgets('without a session nothing is fetched', (tester) async {
    await PreferencesManager().clearSession();
    final context = await host(tester);
    await open(tester, context, 23);
    expect(profiles.reads, isEmpty);
  });
}
