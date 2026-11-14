import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/glass_surface.dart';
import 'package:travibe/core/widgets/glass_confirm_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';
import 'package:travibe/features/follow/screens/follow_users_screen.dart';
import 'package:travibe/features/follow/widgets/follows_you_badge.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/search/data/users_page_model.dart';

import '../profile/fixtures.dart' as profile;

/// The signed-in user (profile fixture id).
const me = '7';

Map<String, dynamic> person(int id, String name, {bool followsYou = false}) => {
  'id': id,
  'name': name,
  'username': name.toLowerCase(),
  'follows_you': followsYou,
  'is_following': false,
};

class _People extends FollowRepo {
  final lists = <FollowListType, List<Map<String, dynamic>>>{
    FollowListType.followers: [
      person(11, 'Ali', followsYou: true),
      person(12, 'Sara', followsYou: true),
    ],
    FollowListType.following: [
      person(21, 'Omar', followsYou: true),
      person(22, 'Nour'),
    ],
  };
  final removed = <String>[];
  ApiError? removeError;

  @override
  Future<UsersPageModel> users({
    required FollowListType type,
    String? userId,
    int page = 1,
    int perPage = 15,
  }) async {
    final users = lists[type]!;
    return UsersPageModel(
      users: users.map(PublicUserModel.fromJson).toList(),
      currentPage: 1,
      lastPage: 1,
      total: users.length,
    );
  }

  @override
  Future<void> removeFollower(String userId) async {
    removed.add(userId);
    if (removeError case final error?) throw error;
    lists[FollowListType.followers]!.removeWhere(
      (user) => user['id'].toString() == userId,
    );
  }

  @override
  Future<PublicUserModel> setFollowing(String userId, bool following) async =>
      PublicUserModel.fromJson({
        'id': int.parse(userId),
        'is_following': following,
      });
}

void main() {
  late _People people;
  late FollowCubit follow;
  late BlockCubit block;
  late CurrentUserCubit current;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('follow-lists');
    people = _People();
    follow = FollowCubit(repo: people);
    block = BlockCubit(follow: follow);
    current = CurrentUserCubit(
      profileRepo: profile.MemoryProfileRepo()..result = profile.profile(),
    );
    await current.load();
  });
  tearDown(() async {
    await block.close();
    await follow.close();
    await current.close();
    await PreferencesManager().clear();
  });

  Future<void> show(
    WidgetTester tester, {
    FollowListType type = FollowListType.followers,
    String userId = me,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        // darkTheme reads AppSizes, so build it inside the ScreenUtil frame.
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: current),
              BlocProvider.value(value: follow),
              BlocProvider.value(value: block),
            ],
            child: FollowUsersScreen(
              type: type,
              userId: userId,
              username: 'mona',
              followersCount: 120,
              followingCount: 80,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder removeX(int id) => find.byKey(ValueKey('remove-follower-$id'));

  testWidgets('my Followers: X per row, no ⋮, no "Follows you" badge', (
    tester,
  ) async {
    await show(tester);
    expect(find.text('Followers (2)'), findsOneWidget);
    expect(find.text('Following (80)'), findsOneWidget);
    expect(removeX(11), findsOneWidget);
    expect(removeX(12), findsOneWidget);
    expect(find.byTooltip('User options'), findsNothing);
    expect(find.byType(FollowsYouBadge), findsNothing);
  });

  testWidgets('Remove confirms, removes the row and updates the count', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(removeX(11));
    await tester.pumpAndSettle();
    expect(find.text('Remove follower?'), findsOneWidget);
    expect(find.text('Remove Ali from your followers?'), findsOneWidget);
    // The shared glass dialog (Log Out look): red Remove, white Cancel, 18.
    expect(find.byType(GlassConfirmDialog), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(GlassConfirmDialog),
        matching: find.byType(GlassSurface),
      ),
      findsOneWidget,
    );
    TextStyle label(String text) => tester
        .widget<RichText>(
          find.descendant(of: find.text(text), matching: find.byType(RichText)),
        )
        .text
        .style!;
    expect(label('Remove').color, const Color(0xFFDD312A));
    expect(label('Remove').fontSize, 18);
    expect(label('Cancel').color, DarkColors.whiteColor);
    expect(label('Cancel').fontSize, 18);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(people.removed, ['11']);
    expect(find.text('Ali'), findsNothing);
    expect(find.text('Sara'), findsOneWidget);
    expect(find.text('Followers (1)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed removal restores the row and shows the error', (
    tester,
  ) async {
    people.removeError = ApiError(message: 'Could not remove');
    await show(tester);
    await tester.tap(removeX(11));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(people.removed, ['11']);
    expect(find.text('Ali'), findsOneWidget);
    expect(find.text('Followers (2)'), findsOneWidget);
    expect(find.text('Could not remove'), findsOneWidget);
  });

  testWidgets('Cancel keeps the row and calls nothing', (tester) async {
    await show(tester);
    await tester.tap(removeX(12));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(people.removed, isEmpty);
    expect(find.text('Sara'), findsOneWidget);
    expect(find.text('Followers (2)'), findsOneWidget);
  });

  testWidgets('my Following: badge only for people who follow me back', (
    tester,
  ) async {
    await show(tester, type: FollowListType.following);
    expect(find.text('Following (2)'), findsOneWidget);
    expect(find.byType(FollowsYouBadge), findsOneWidget);
    expect(find.text('Follows you'), findsOneWidget);
    // The badge sits above Omar's picture row, not next to Nour.
    expect(
      tester.getTopLeft(find.byType(FollowsYouBadge)).dy,
      lessThan(tester.getTopLeft(find.text('Omar')).dy),
    );
    expect(removeX(21), findsNothing);
    expect(find.byTooltip('User options'), findsNothing);
  });

  for (final type in [FollowListType.followers, FollowListType.following]) {
    testWidgets("another user's $type list has no X and no ⋮", (tester) async {
      await show(tester, type: type, userId: '8');
      expect(find.byTooltip('Remove follower'), findsNothing);
      expect(find.byTooltip('User options'), findsNothing);
      expect(
        find.byKey(
          ValueKey('follow-pill-${type == FollowListType.followers ? 11 : 21}'),
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('my own row has no Follow pill', (tester) async {
    people.lists[FollowListType.followers]!.add(person(7, 'Mona'));
    await show(tester, userId: '8');
    expect(find.byKey(const ValueKey('own-user-row')), findsOneWidget);
    expect(find.byKey(const ValueKey('follow-pill-7')), findsNothing);
    expect(find.byKey(const ValueKey('follow-pill-11')), findsOneWidget);
  });
}
