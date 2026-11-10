import '../../helpers/cursor_fixtures.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:travibe/features/shares/data/post_share_actions.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/post_card.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/home/data/posts_page_model.dart';
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/features/home/screens/home_screen.dart';
import 'package:travibe/features/shares/cubit/shares_cubit.dart';
import 'package:travibe/features/shares/data/share_model.dart';
import 'package:travibe/features/shares/widgets/share_post_dialog.dart';
import '../home/home_experience_fixtures.dart' as home;
import 'fixtures.dart';

class HomePosts extends PostsRepo {
  HomePosts(this.shares);
  final MemorySharesRepo shares;
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
        'user_id': 2,
        'user': {'id': 2, 'name': 'Sara'},
        'content': 'Post text',
        'visibility': 'public',
        'shares_count': shares.counts[10],
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
  late MemorySharesRepo repo;
  late SharesCubit cubit;
  setUp(() {
    repo = MemorySharesRepo();
    cubit = SharesCubit(repo: repo);
    cubit.acceptCounts({10: 2}, requestRevision: 0);
  });
  tearDown(() => cubit.close());

  Future<void> show(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    SharePostDialog.show(context, postId: 10, shares: cubit),
                child: const Text('Open share'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open share'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'opening checks status without sharing; Cancel leaves everything unchanged',
    (tester) async {
      await show(tester);
      expect(find.text('Share post?'), findsOneWidget);
      expect(repo.creates, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(SharePostDialog), findsNothing);
      expect(cubit.post(10).count, 2);
    },
  );
  testWidgets('confirmation submits caption once and returns after success', (
    tester,
  ) async {
    await show(tester);
    await tester.enterText(find.byType(TextField), 'A note');
    repo.createGate = Completer<ShareModel>();
    await tester.tap(find.text('Share'));
    await tester.pump();
    expect(repo.creates, hasLength(1));
    expect(repo.creates.single.request.toJson(), {
      'platform': 'internal',
      'comment': 'A note',
    });
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Please wait…'));
    expect(repo.creates, hasLength(1));
    repo.createGate!.complete(share());
    await tester.pumpAndSettle();
    expect(find.byType(SharePostDialog), findsNothing);
    expect(cubit.post(10).count, 3);
  });
  testWidgets(
    'failure preserves note and retry rechecks status before resubmitting',
    (tester) async {
      await show(tester);
      await tester.enterText(find.byType(TextField), 'Keep this draft');
      repo.createError = ApiError(message: 'Network failed');
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(find.text('Network failed'), findsOneWidget);
      expect(find.textContaining('ApiError'), findsNothing);
      repo.createError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Keep this draft',
      );
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(repo.creates, hasLength(2));
      expect(find.byType(SharePostDialog), findsNothing);
    },
  );
  testWidgets(
    'confirmed deletion offers count-only retry without repeating DELETE',
    (tester) async {
      repo.records[10] = [share()];
      await cubit.inspect(10);
      repo.countError = ApiError(message: 'Count unavailable');
      await cubit.delete(10);
      await show(tester);
      expect(find.text('Retry count'), findsOneWidget);
      repo.countError = null;
      await tester.tap(find.text('Retry count'));
      await tester.pumpAndSettle();
      expect(find.text('Retry count'), findsNothing);
      expect(repo.deletes, hasLength(1));
      expect(repo.creates, isEmpty);
    },
  );
  testWidgets(
    'shares-list error is retryable and never enables an unchecked mutation',
    (tester) async {
      repo.listError = ApiError(message: 'Unauthorized', statusCode: 401);
      await show(tester);
      expect(find.text('Unauthorized'), findsOneWidget);
      expect(find.text('Share'), findsNothing);
      repo.listError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Share'), findsOneWidget);
      expect(repo.creates, isEmpty);
    },
  );
  testWidgets('small-screen keyboard and long notes do not overflow', (
    tester,
  ) async {
    await show(tester, size: const Size(320, 480));
    tester.view.viewInsets = const FakeViewPadding(bottom: 150);
    addTearDown(tester.view.resetViewInsets);
    await tester.enterText(find.byType(TextField), 'x' * 501);
    await tester.pumpAndSettle();
    expect(
      find.text('Share notes must be 500 characters or fewer.'),
      findsOneWidget,
    );
    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Share'),
    );
    expect(button.onPressed, isNull);
    expect(repo.creates, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Home shares actual post text without reposting or changing either feed count',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(PostShareActions.channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () =>
            messenger.setMockMethodCallHandler(PostShareActions.channel, null),
      );
      final account = home.AccountRepo()..followingCount = 1;
      final people = home.PeopleRepo(account);
      final follow = FollowCubit(repo: people);
      final block = BlockCubit(follow: follow);
      addTearDown(follow.close);
      addTearDown(block.close);
      repo.viewerId = 1;
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
                child: HomeScreen(
                  accountRepo: account,
                  postsRepo: HomePosts(repo),
                  sharesRepo: repo,
                ),
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
      expect(repo.creates, isEmpty);
      expect(find.text('Send Post'), findsOneWidget);
      expect(find.text('Share to your profile'), findsNothing);
      expect(find.text('Unshare from your profile'), findsNothing);
      await tester.tap(find.text('More Options'));
      await tester.pumpAndSettle();
      expect(calls.single.method, 'share');
      expect((calls.single.arguments as Map)['text'], 'Post text');
      expect((calls.single.arguments as Map).containsKey('url'), isFalse);
      expect(repo.creates, isEmpty);
      expect(repo.deletes, isEmpty);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(tester.widget<PostCard>(find.byType(PostCard)).shares, '2');
      await tester.tap(find.text('Following').first);
      await tester.pumpAndSettle();
      final card = tester.widget<PostCard>(find.byType(PostCard));
      expect(card.shares, '2');
      expect(card.isLiked, isTrue);
      expect(card.comments, '4');
      expect(tester.takeException(), isNull);
    },
  );
}
