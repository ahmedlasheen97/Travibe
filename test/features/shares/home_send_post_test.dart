import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/home/data/posts_page_model.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/features/home/screens/home_screen.dart';
import 'package:travibe/features/shares/data/post_share_actions.dart';
import 'package:travibe/features/shares/widgets/send_post_sheet.dart';
import '../../helpers/cursor_fixtures.dart';
import '../home/home_experience_fixtures.dart' as home;

class HomePosts extends PostsRepo {
  @override
  Future<PostsPageModel> getPosts({
    FeedType feed = FeedType.explore,
    String? cursor,
    int perPage = 15,
  }) async => PostsPageModel(
    pagination: fixtureMeta(current: 1, last: 1),
    posts: [
      PostModel.fromJson({
        'id': 10,
        'url': 'https://travibeapp.com/p/10',
        'user_id': 2,
        'user': {'id': 2, 'name': 'Sara'},
        'content': 'Post text',
        'visibility': 'public',
        'comments_count': 4,
        'likes_count': 1,
        'is_liked': true,
      }),
    ],
    currentPage: 1,
    lastPage: 1,
    total: 1,
  );
}

void main() {
  testWidgets('Home share icon opens Send Post and shares the post link', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(PostShareActions.channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(PostShareActions.channel, null),
    );
    final account = home.AccountRepo()..followingCount = 1;
    final follow = FollowCubit(repo: home.PeopleRepo(account));
    final block = BlockCubit(follow: follow);
    addTearDown(follow.close);
    addTearDown(block.close);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: follow),
                BlocProvider.value(value: block),
              ],
              child: HomeScreen(accountRepo: account, postsRepo: HomePosts()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final icon = find.byKey(const ValueKey('post-share'));
    await tester.ensureVisible(icon);
    await tester.tap(icon);
    await tester.pumpAndSettle();
    expect(find.byType(SendPostSheet), findsOneWidget);
    await tester.tap(find.text('More Options'));
    await tester.pumpAndSettle();
    expect(calls.single.method, 'share');
    expect(
      (calls.single.arguments as Map)['url'],
      'https://travibeapp.com/p/10',
    );
    expect(tester.takeException(), isNull);
  });
}
