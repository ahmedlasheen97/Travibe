import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/features/shares/data/post_share_actions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/post_card.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/cubit/profile_cubit.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'package:travibe/features/profile/screens/profile_screen.dart';
import 'package:travibe/features/profile/widgets/profile_avatar.dart';
import 'package:travibe/features/profile/widgets/profile_header_info.dart';
import 'package:travibe/features/profile/widgets/profile_shimmer.dart';
import 'package:travibe/features/profile/widgets/profile_stats.dart';
import 'package:travibe/features/profile/widgets/profile_tabs.dart';
import '../saved/fixtures.dart' as saved;
import 'package:travibe/features/home/data/posts_repo.dart';
import 'package:travibe/features/home/data/posts_page_model.dart';
import 'package:travibe/root.dart';
import 'package:travibe/features/follow/screens/follow_users_screen.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';
import '../home/home_experience_fixtures.dart' as home;
import 'fixtures.dart';
import 'profile_posts_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts = FontLoader('Plus Jakarta Sans')
      ..addFont(rootBundle.load('assets/fonts/PlusJakartaSans-Regular.ttf'));
    await fonts.load();
  });
  late MemoryProfileRepo profiles;
  late AuthorPostsRepo posts;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('profile-ui-test');
    profiles = MemoryProfileRepo();
    posts = AuthorPostsRepo();
  });
  tearDown(() => PreferencesManager().clear());

  Future<void> show(
    WidgetTester tester, {
    bool settle = true,
    ValueNotifier<int>? signal,
    CurrentUserCubit? currentUser,
    Widget? child,
    Size size = const Size(390, 844),
    double textScale = 1,
    EdgeInsets padding = EdgeInsets.zero,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final content =
        child ??
        ProfileScreen(
          profileRepo: profiles,
          postsRepo: posts,
          refreshSignal: signal,
        );
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              padding: padding,
            ),
            child: child!,
          ),
          home: currentUser == null
              ? content
              : BlocProvider.value(value: currentUser, child: content),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> startRefresh(WidgetTester tester) async {
    unawaited(
      tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh(),
    );
    await tester.pump();
  }

  testWidgets(
    'initial skeleton has one dark animation, real header and no spinners',
    (tester) async {
      profiles.hold = true;
      await show(tester, settle: false);
      expect(find.byType(ProfileShimmer), findsOneWidget);
      expect(find.byType(Shimmer), findsOneWidget);
      expect(find.text('My Profile'), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.widget<Shimmer>(find.byType(Shimmer)).enabled, isTrue);
      profiles.reads.single.result.complete(profile());
      await tester.pumpAndSettle();
      expect(find.byType(ProfileShimmer), findsNothing);
      expect(find.text('Mona Hassan'), findsOneWidget);
    },
  );

  testWidgets(
    'cached resource displays immediately while its background read is pending',
    (tester) async {
      final current = CurrentUserCubit(profileRepo: profiles);
      addTearDown(current.close);
      await current.load();
      profiles.hold = true;
      await show(tester, currentUser: current, settle: false);
      expect(find.text('Mona Hassan'), findsOneWidget);
      expect(find.byType(ProfileShimmer), findsNothing);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      profiles.reads.last.result.complete(profile());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'profile displays without waiting for author posts; posts use skeleton only',
    (tester) async {
      posts.holdAuthors = true;
      await show(tester, settle: false);
      expect(find.text('Mona Hassan'), findsOneWidget);
      expect(find.byType(ProfilePostSkeleton), findsOneWidget);
      expect(find.byType(ProfileShimmer), findsNothing);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      posts.authorReads.single.result.complete(authorPage(7, [101]));
      await tester.pumpAndSettle();
      expect(find.byType(ProfilePostSkeleton), findsNothing);
    },
  );

  testWidgets(
    'coordinated refresh has one top spinner and keeps card elements and geometry',
    (tester) async {
      await show(tester, padding: const EdgeInsets.only(top: 32));
      final avatar = tester.getTopLeft(find.byType(ProfileAvatar));
      final stats = tester.getTopLeft(find.byType(ProfileStats));
      final card = tester.element(find.byType(PostCard).first);
      profiles.hold = true;
      posts.holdAuthors = true;
      await startRefresh(tester);
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      final indicator = tester.widget<CupertinoActivityIndicator>(
        find.byType(CupertinoActivityIndicator),
      );
      expect(indicator.radius, 15);
      expect(indicator.color, DarkColors.whiteColor);
      final rect = tester.getRect(find.byType(CupertinoActivityIndicator));
      expect(rect.center.dx, 195);
      expect(rect.top, greaterThanOrEqualTo(32));
      expect(rect.bottom, lessThanOrEqualTo(avatar.dy));
      expect(tester.getTopLeft(find.byType(ProfileAvatar)), avatar);
      expect(tester.getTopLeft(find.byType(ProfileStats)), stats);
      expect(tester.element(find.byType(PostCard).first), same(card));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(RefreshProgressIndicator), findsNothing);
      expect(find.byType(ProfileShimmer), findsNothing);
      profiles.reads.last.result.complete(profile());
      await tester.pump();
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      posts.authorReads.last.result.complete(authorPage(7, [101]));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(tester.element(find.byType(PostCard).first), same(card));
    },
  );

  testWidgets(
    'pull gesture suppresses native indicator and uses the coordinated overlay',
    (tester) async {
      await show(tester);
      profiles.hold = true;
      posts.holdAuthors = true;
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 500));
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(find.byType(RefreshProgressIndicator), findsNothing);
      profiles.reads.last.result.complete(profile());
      posts.authorReads.last.result.complete(authorPage(7, [101]));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
    },
  );

  testWidgets(
    'refresh failure resets spinner, retains data and remains retryable',
    (tester) async {
      await show(tester);
      profiles.hold = true;
      posts.holdAuthors = true;
      await startRefresh(tester);
      profiles.reads.last.result.completeError(
        ApiError(message: 'Profile offline'),
      );
      posts.authorReads.last.result.completeError(
        ApiError(message: 'Posts offline'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(find.text('Mona Hassan'), findsOneWidget);
      expect(find.byType(PostCard), findsOneWidget);
      expect(find.text('Profile offline'), findsOneWidget);
      await startRefresh(tester);
      profiles.reads.last.result.complete(profile());
      posts.authorReads.last.result.complete(authorPage(7, [101]));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
    },
  );

  testWidgets('repeat pull and re-tap events share one request pair', (
    tester,
  ) async {
    final signal = ValueNotifier(0);
    addTearDown(signal.dispose);
    await show(tester, signal: signal);
    profiles.hold = true;
    posts.holdAuthors = true;
    await startRefresh(tester);
    await startRefresh(tester);
    signal.value++;
    signal.value++;
    await tester.pump();
    expect(profiles.reads, hasLength(2));
    expect(posts.authorReads, hasLength(2));
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    profiles.reads.last.result.complete(profile());
    posts.authorReads.last.result.complete(authorPage(7, [101]));
    await tester.pumpAndSettle();
  });

  testWidgets('About selection and scroll position survive refresh', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    final scroll = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    scroll.jumpTo(90);
    await tester.pump();
    profiles.hold = true;
    await startRefresh(tester);
    expect(
      tester.widget<ProfileTabs>(find.byType(ProfileTabs)).selectedIndex,
      1,
    );
    expect(scroll.pixels, 90);
    expect(posts.authorReads, hasLength(1));
    profiles.reads.last.result.complete(profile());
    await tester.pumpAndSettle();
    expect(scroll.pixels, 90);
    expect(
      tester.widget<ProfileTabs>(find.byType(ProfileTabs)).selectedIndex,
      1,
    );
  });

  testWidgets(
    'Saved refresh keeps the selected tab and waits for profile plus saved posts',
    (tester) async {
      final signal = ValueNotifier(0);
      addTearDown(signal.dispose);
      await show(tester, signal: signal);
      await tester.tap(find.text('Saved'));
      await tester.pumpAndSettle();
      final card = tester.element(find.byType(PostCard).first);
      profiles.hold = true;
      posts.holdReads = true;
      signal.value++;
      signal.value++;
      await tester.pump();
      expect(profiles.reads, hasLength(2));
      expect(posts.reads, hasLength(2));
      expect(posts.authorReads, hasLength(1));
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(
        tester.widget<ProfileTabs>(find.byType(ProfileTabs)).selectedIndex,
        2,
      );
      expect(tester.element(find.byType(PostCard).first), same(card));
      profiles.reads.last.result.complete(profile());
      await tester.pump();
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      posts.reads.last.result.complete(saved.savedPage([1]));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.element(find.byType(PostCard).first), same(card));
    },
  );

  testWidgets(
    'background profile revalidation never shows the explicit refresh overlay',
    (tester) async {
      await show(tester);
      final cubit = tester
          .element(find.byType(ProfileHeaderInfo))
          .read<ProfileCubit>();
      profiles.hold = true;
      final request = cubit.refresh();
      await tester.pump();
      expect(find.text('Mona Hassan'), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(ProfileShimmer), findsNothing);
      profiles.reads.last.result.complete(profile());
      await request;
      await tester.pumpAndSettle();
    },
  );

  testWidgets('pagination retains cursor behavior without a page-top spinner', (
    tester,
  ) async {
    posts.authorLast = 2;
    await show(tester);
    posts.holdAuthors = true;
    await tester.ensureVisible(find.text('Load more'));
    await tester.tap(find.text('Load more'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('profile-refresh-indicator')),
      findsNothing,
    );
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    expect(posts.authorReads.last.page, 2);
    posts.authorReads.last.result.complete(
      authorPage(7, [101, 102], page: 2, last: 2),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PostCard), findsNWidgets(2));
  });

  testWidgets(
    'statistics share one rounded border and two dividers with orange counts',
    (tester) async {
      await show(tester);
      final scope = find.byType(ProfileStats);
      final containers = tester.widgetList<Container>(
        find.descendant(of: scope, matching: find.byType(Container)),
      );
      final bordered = containers.where(
        (c) =>
            c.decoration is BoxDecoration &&
            (c.decoration! as BoxDecoration).border != null &&
            (c.decoration! as BoxDecoration).borderRadius != null,
      );
      expect(bordered, hasLength(1));
      expect(
        (bordered.single.decoration! as BoxDecoration).borderRadius,
        BorderRadius.circular(20),
      );
      expect(
        find.descendant(of: scope, matching: find.byType(VerticalDivider)),
        findsNWidgets(2),
      );
      for (final label in ['5', '12', '4']) {
        expect(
          tester
              .widget<Text>(
                find.descendant(of: scope, matching: find.text(label)),
              )
              .style!
              .color,
          DarkColors.primaryColor,
        );
      }
      final sections = tester.widgetList<Expanded>(
        find.descendant(of: scope, matching: find.byType(Expanded)),
      );
      expect(sections.map((e) => e.flex), [1, 1, 1]);
    },
  );

  testWidgets(
    'bio wraps naturally into two lines and actions are compact equal grey pills',
    (tester) async {
      final bio =
          'A long bio 🌍\nwith several lines\nand more text that remains stored';
      profiles.result = ProfileModel.fromJson({
        ...profileJson(),
        'bio': bio,
        'url': 'https://example.invalid/u/7',
      });
      await show(tester);
      final text = tester.widget<Text>(find.text(bio));
      expect(text.style!.color, DarkColors.whiteColor);
      expect(text.style!.fontSize, 16);
      expect(text.style!.fontFamily, 'Plus Jakarta Sans');
      expect(text.style!.fontWeight, FontWeight.w400);
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(text.softWrap, isTrue);
      expect(text.textAlign, TextAlign.center);
      expect(profiles.result!.bio, bio);
      final share = find.widgetWithText(FilledButton, 'Share Profile');
      final edit = find.widgetWithText(FilledButton, 'Edit Profile');
      expect(tester.getSize(share), tester.getSize(edit));
      expect(tester.getSize(edit).height, 44);
      expect(tester.getTopLeft(edit).dx - tester.getTopRight(share).dx, 12);
      expect(tester.widget<FilledButton>(share).onPressed, isNotNull);
      expect(tester.widget<FilledButton>(edit).onPressed, isNotNull);
      for (final finder in [share, edit]) {
        expect(
          tester
              .widget<FilledButton>(finder)
              .style!
              .backgroundColor!
              .resolve({}),
          DarkColors.darkgreyColor,
        );
      }
    },
  );

  testWidgets('Share Profile shares the backend url via the native sheet', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(PostShareActions.channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(PostShareActions.channel, null),
    );
    profiles.result = ProfileModel.fromJson({
      ...profileJson(),
      'url': 'https://example.invalid/u/7',
    });
    await show(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Share Profile'));
    await tester.pump();
    expect(calls.single.method, 'share');
    final args = calls.single.arguments as Map;
    expect(args['url'], 'https://example.invalid/u/7');
    expect(args.containsKey('text'), isFalse);
    expect(args['width'], greaterThan(0));
  });

  testWidgets('without a backend url Share Profile is hidden', (tester) async {
    for (final url in [
      null,
      '',
      'http://example.invalid/u/7',
      'travibe://users/7',
    ]) {
      profiles.result = ProfileModel.fromJson({...profileJson(), 'url': url});
      await show(tester);
      expect(find.text('Share Profile'), findsNothing, reason: '$url');
      expect(find.widgetWithText(FilledButton, 'Edit Profile'), findsOneWidget);
    }
  });

  for (final width in [390.0, 320.0]) {
    testWidgets('bio width is constrained and centered at $width', (
      tester,
    ) async {
      const longBio =
          'Exploring the world, meeting people and sharing stories. '
          'Enjoying beautiful cities, local culture and new adventures every day. '
          'More memories and many more places still to discover.';
      await show(
        tester,
        size: Size(width, 844),
        child: const Scaffold(
          body: Center(
            child: ProfileHeaderInfo(
              name: 'Mona',
              username: '@mona',
              bio: longBio,
            ),
          ),
        ),
      );
      final rect = tester.getRect(find.text(longBio));
      expect(rect.width, width == 390 ? 290 : 240);
      expect(rect.center.dx, closeTo(width / 2, .01));
      expect(tester.widget<Text>(find.text(longBio)).data, longBio);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.text(longBio),
      );
      expect(paragraph.didExceedMaxLines, isTrue);
      await show(
        tester,
        size: Size(width, 844),
        child: const Scaffold(
          body: Center(
            child: ProfileHeaderInfo(
              name: 'Mona',
              username: '@mona',
              bio: 'Short bio',
            ),
          ),
        ),
      );
      final shortRect = tester.getRect(find.text('Short bio'));
      expect(shortRect.width, lessThan(240));
      expect(shortRect.center.dx, closeTo(width / 2, .01));
    });
  }

  testWidgets('empty bio reserves no paragraph height', (tester) async {
    Future<double> height(String bio) async {
      await show(
        tester,
        child: Scaffold(
          body: ProfileHeaderInfo(name: 'Mona', username: '@mona', bio: bio),
        ),
      );
      return tester.getSize(find.byType(ProfileHeaderInfo)).height;
    }

    final empty = await height('');
    expect(await height('   '), empty);
    expect(await height('Short bio'), greaterThan(empty));
  });

  testWidgets('disposal and session replacement cannot expose old responses', (
    tester,
  ) async {
    await show(tester);
    profiles.hold = true;
    posts.holdAuthors = true;
    await startRefresh(tester);
    final oldProfile = profiles.reads.last;
    final oldPosts = posts.authorReads.last;
    await PreferencesManager().clearSession();
    await tester.pump();
    oldProfile.result.complete(profile(name: 'Old account'));
    oldPosts.result.complete(authorPage(7, [101]));
    await tester.pump();
    expect(find.text('Old account'), findsNothing);
    expect(find.byType(PostCard), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('small screens and larger text do not overflow', (tester) async {
    posts.authors[7] = [];
    profiles.result = ProfileModel.fromJson({
      ...profileJson(),
      'bio': 'A natural short bio 🌍',
    });
    await show(tester, size: const Size(320, 568), textScale: 1.6);
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<Text>(find.text('A natural short bio 🌍')).maxLines,
      2,
    );
  });

  testWidgets(
    'Root Profile re-tap refreshes once; returning from another tab uses cache',
    (tester) async {
      final feeds = home.EmptyPostsRepo();
      final account = home.AccountRepo();
      await show(
        tester,
        child: Root(
          postsRepo: _RootPosts(posts, feeds),
          profileRepo: profiles,
          homeAccountRepo: account,
          followRepo: home.PeopleRepo(account),
        ),
      );
      BottomNavigationBar nav() =>
          tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      nav().onTap!(4);
      await tester.pumpAndSettle();
      profiles.hold = true;
      posts.holdAuthors = true;
      nav().onTap!(4);
      nav().onTap!(4);
      await tester.pump();
      expect(profiles.reads, hasLength(2));
      expect(posts.authorReads, hasLength(2));
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      profiles.reads.last.result.complete(profile());
      posts.authorReads.last.result.complete(authorPage(7, [101]));
      await tester.pumpAndSettle();
      final reads = profiles.reads.length;
      nav().onTap!(0);
      await tester.pumpAndSettle();
      nav().onTap!(4);
      await tester.pumpAndSettle();
      expect(profiles.reads.length, reads);
      expect(posts.authorReads, hasLength(2));
      await tester.tap(find.text('Followers'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FollowUsersScreen>(find.byType(FollowUsersScreen)).type,
        FollowListType.followers,
      );
      expect(
        tester.widget<FollowUsersScreen>(find.byType(FollowUsersScreen)).userId,
        '7',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ProfileStats),
          matching: find.text('Following'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<FollowUsersScreen>(find.byType(FollowUsersScreen)).type,
        FollowListType.following,
      );
      expect(
        tester.widget<FollowUsersScreen>(find.byType(FollowUsersScreen)).userId,
        '7',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
    },
  );
}

class _RootPosts extends PostsRepo {
  _RootPosts(this.authors, this.feeds);
  final AuthorPostsRepo authors;
  final home.EmptyPostsRepo feeds;
  @override
  Future<PostsPageModel> getUserPosts({
    required int userId,
    String? cursor,
    int perPage = 15,
  }) => authors.getUserPosts(userId: userId, cursor: cursor, perPage: perPage);
  @override
  Future<PostsPageModel> getPosts({
    FeedType feed = FeedType.explore,
    String? cursor,
    int perPage = 15,
  }) => feeds.getPosts(feed: feed, cursor: cursor, perPage: perPage);
}
