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
import 'package:travibe/features/likes/data/like_model.dart';
import 'package:travibe/features/likes/widgets/liked_by_sheet.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import '../profile/fixtures.dart' as profile;
import 'likers_fixtures.dart';

void main() {
  late FollowWrites follows;
  late FollowCubit follow;
  late BlockCubit blocks;
  late CurrentUserCubit current;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('account-7');
    follows = FollowWrites();
    follow = FollowCubit(repo: follows);
    blocks = BlockCubit(follow: follow);
    current = CurrentUserCubit(
      profileRepo: profile.MemoryProfileRepo()..result = profile.profile(),
    );
    await current.load();
  });
  tearDown(() async {
    await blocks.close();
    await follow.close();
    await current.close();
    await PreferencesManager().clear();
  });

  Future<void> open(
    WidgetTester tester,
    LikersRepo repo, {
    int count = 3,
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
          home: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: follow),
              BlocProvider.value(value: blocks),
              BlocProvider.value(value: current),
            ],
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => LikedBySheet.show(
                    context,
                    postId: 10,
                    count: count,
                    repo: repo,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Finder inRow(int id, Finder matching) => find.descendant(
    of: find.byKey(ValueKey('liker-$id')),
    matching: matching,
  );

  testWidgets('lists likers with handle, follow state and the post count', (
    tester,
  ) async {
    final repo = LikersRepo([
      [liker(7), liker(8), liker(9, following: true)],
    ]);
    await open(tester, repo, count: 1234);
    expect(repo.requests.single.target, const LikeTarget.post(10));
    expect(find.text('Liked by'), findsOneWidget);
    expect(find.text('1.2K'), findsOneWidget);
    expect(find.text('User 8'), findsOneWidget);
    expect(find.text('@user8'), findsOneWidget);
    expect(inRow(8, find.text('Follow')), findsOneWidget);
    expect(inRow(9, find.text('Following')), findsOneWidget);
    // My own row: no Follow and no ⋮.
    expect(inRow(7, find.text('Follow')), findsNothing);
    expect(inRow(7, find.byIcon(Icons.more_vert)), findsNothing);
    expect(inRow(8, find.byIcon(Icons.more_vert)), findsOneWidget);
  });

  testWidgets('Follow goes through the shared FollowCubit', (tester) async {
    await open(
      tester,
      LikersRepo([
        [liker(8)],
      ]),
    );
    await tester.tap(inRow(8, find.text('Follow')));
    await tester.pumpAndSettle();
    expect(follows.requests, ['8']);
    expect(follow.state.following['8'], isTrue);
    expect(inRow(8, find.text('Following')), findsOneWidget);
  });

  testWidgets('row ⋮ offers Block user only', (tester) async {
    await open(
      tester,
      LikersRepo([
        [liker(8)],
      ]),
    );
    await tester.tap(inRow(8, find.byIcon(Icons.more_vert)));
    await tester.pumpAndSettle();
    expect(find.text('Block user'), findsOneWidget);
    expect(find.text('Hide post'), findsNothing);
  });

  testWidgets('empty state', (tester) async {
    await open(tester, LikersRepo([]), count: 0);
    expect(find.text('No likes yet'), findsOneWidget);
  });

  testWidgets('error state retries', (tester) async {
    final repo = LikersRepo([
      [liker(8)],
    ])..error = ApiError(message: 'Likes failed');
    await open(tester, repo);
    expect(find.text('Likes failed'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('User 8'), findsOneWidget);
    expect(repo.requests, hasLength(2));
  });

  testWidgets('scrolling near the end loads the next cursor page', (
    tester,
  ) async {
    final repo = LikersRepo([
      [for (var id = 20; id < 35; id++) liker(id)],
      [liker(99)],
    ]);
    await open(tester, repo);
    expect(repo.requests, hasLength(1));
    await tester.drag(find.text('User 22'), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(repo.requests.map((r) => r.cursor), [null, 'page-1']);
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.text('User 99'), findsOneWidget);
  });
}
