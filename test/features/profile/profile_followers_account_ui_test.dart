import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/block/data/block_repo.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_users_cubit.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';
import 'package:travibe/features/follow/screens/follow_users_screen.dart';
import 'package:travibe/features/follow/widgets/follow_user_tile.dart';
import 'package:travibe/features/profile/screens/profile_screen.dart';
import 'package:travibe/features/profile/widgets/profile_empty_state.dart';
import 'package:travibe/features/profile/widgets/logout_dialog_widget.dart';
import 'package:travibe/features/search/data/users_page_model.dart';
import 'package:travibe/features/search/widgets/person_result_tile.dart';
import 'fixtures.dart';
import 'profile_posts_fixtures.dart';
import 'profile_account_actions_test.dart' show LogoutRepo;
import 'account_deletion_test.dart' as deletion;
import 'package:travibe/features/profile/screens/delete_account_screen.dart';
import 'package:travibe/features/buddies/screens/buddies_screen.dart';

PublicUserModel person(
  int id, {
  bool following = false,
  bool blocked = false,
  bool long = false,
}) => PublicUserModel.fromJson({
  'id': id,
  'name': long
      ? 'A very long traveler name that must stay inside the card'
      : 'Traveler $id',
  'username': long
      ? 'a_very_long_username_that_cannot_overflow'
      : 'traveler$id',
  'avatar_url': null,
  'is_following': following,
  'is_blocked': blocked,
  'followers_count': 7,
  'following_count': 8,
});

class _Read {
  _Read(this.type, this.page);
  final FollowListType type;
  final int page;
  final result = Completer<UsersPageModel>();
}

class _People extends FollowRepo {
  final reads = <_Read>[];
  final mutations = <(String, bool)>[];
  bool hold = false, empty = false, long = false;
  int last = 1;
  ApiError? error;
  Completer<PublicUserModel>? mutation;
  UsersPageModel page(FollowListType type, int page) => UsersPageModel(
    users: empty
        ? []
        : [
            person(
              page == 2
                  ? 33
                  : type == FollowListType.followers
                  ? 11
                  : 22,
              long: long,
            ),
          ],
    currentPage: page,
    lastPage: last,
    total: empty ? 0 : last,
  );
  @override
  Future<UsersPageModel> users({
    required FollowListType type,
    String? userId,
    int page = 1,
    int perPage = 15,
  }) async {
    final read = _Read(type, page);
    reads.add(read);
    if (hold) return read.result.future;
    if (error != null) throw error!;
    return this.page(type, page);
  }

  @override
  Future<PublicUserModel> setFollowing(String id, bool following) async {
    mutations.add((id, following));
    return mutation == null
        ? person(int.parse(id), following: following)
        : mutation!.future;
  }
}

class _Blocks extends BlockRepo {
  final calls = <(String, bool)>[];
  @override
  Future<BlockStatus> status(String id) async =>
      BlockStatus(userId: id, isBlocked: false);
  @override
  Future<PublicUserModel> setBlocked(String id, bool blocked) async {
    calls.add((id, blocked));
    return person(int.parse(id), blocked: blocked);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
          'Plus Jakarta Sans',
        )..addFont(rootBundle.load('assets/fonts/PlusJakartaSans-Regular.ttf')))
        .load();
    for (final name in ['emptypic', 'emptypost', 'emptyitems']) {
      await SvgAssetLoader('assets/images/profile/$name.svg').loadBytes(null);
    }
  });
  late _People people;
  late _Blocks blocks;
  late FollowCubit follow;
  late BlockCubit block;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('mock-ui-session');
    people = _People();
    blocks = _Blocks();
    follow = FollowCubit(repo: people);
    block = BlockCubit(follow: follow, repo: blocks);
  });
  tearDown(() async {
    await block.close();
    await follow.close();
    await PreferencesManager().clear();
  });

  Future<void> show(
    WidgetTester tester, {
    FollowListType type = FollowListType.followers,
    bool settle = true,
    double width = 390,
    double height = 844,
    double scale = 1,
    VoidCallback? explore,
    Widget? child,
    bool highContrast = false,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              highContrast: highContrast,
            ),
            child: child!,
          ),
          home: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: follow),
              BlocProvider.value(value: block),
            ],
            child:
                child ??
                FollowUsersScreen(
                  type: type,
                  userId: '7',
                  username: 'mona',
                  followersCount: 12,
                  followingCount: 4,
                  onExplorePeople: explore,
                ),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  for (final type in [FollowListType.followers, FollowListType.following]) {
    testWidgets(
      'glass Back returns from $type without changing relationship state',
      (tester) async {
        await show(
          tester,
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    FollowUsersScreen.open(context, type: type, userId: '7'),
                child: const Text('Open people'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open people'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Back'), findsOneWidget);
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(find.text('Open people'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  String? svgAsset(WidgetTester tester) {
    final svg = tester.widget<SvgPicture>(find.byType(SvgPicture).last);
    return (svg.bytesLoader as SvgAssetLoader).assetName;
  }

  testWidgets(
    'compact card has real identity and relationship action without exposed utility labels',
    (tester) async {
      await show(tester);
      expect(find.text('@mona'), findsOneWidget);
      expect(find.text('Followers (1)'), findsOneWidget);
      expect(find.text('Following (4)'), findsOneWidget);
      expect(find.text('Traveler 11'), findsOneWidget);
      expect(find.text('@traveler11'), findsOneWidget);
      expect(find.text('Block'), findsNothing);
      expect(find.text('7 followers'), findsNothing);
      expect(find.text('8 following'), findsNothing);
      expect(find.byTooltip('User options'), findsOneWidget);
      expect(tester.getSize(find.byType(FollowUserTile)).height, lessThan(100));
      expect(
        tester.widget<PersonResultTile>(find.byType(PersonResultTile)).onTap,
        isNotNull,
      );
    },
  );

  testWidgets(
    'independent tabs request distinct lists and keep their cached pages',
    (tester) async {
      await show(tester);
      await tester.tap(find.text('Following (4)'));
      await tester.pumpAndSettle();
      expect(find.text('Traveler 22'), findsOneWidget);
      expect(find.text('Traveler 11'), findsNothing);
      await tester.tap(find.text('Followers (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Traveler 11'), findsOneWidget);
      expect(people.reads.map((r) => r.type), [
        FollowListType.followers,
        FollowListType.following,
      ]);
    },
  );

  testWidgets(
    'follow optimistically updates, coalesces requests and rolls back errors',
    (tester) async {
      await show(tester);
      people.mutation = Completer<PublicUserModel>();
      await tester.tap(find.text('Follow'));
      await tester.pump();
      expect(people.mutations, [('11', true)]);
      expect(
        tester
            .widget<PersonResultTile>(find.byType(PersonResultTile))
            .onFollowTap,
        isNull,
      );
      people.mutation!.completeError(ApiError(message: 'Offline'));
      await tester.pumpAndSettle();
      expect(find.text('Follow'), findsOneWidget);
      expect(find.text('Offline'), findsOneWidget);
      people.mutation = null;
      await tester.tap(find.text('Follow'));
      await tester.pumpAndSettle();
      expect(find.text('Following'), findsOneWidget);
      await tester.tap(find.text('Following'));
      await tester.pumpAndSettle();
      expect(people.mutations.last, ('11', false));
      expect(find.text('Follow'), findsOneWidget);
    },
  );

  testWidgets('overflow retains Block confirmation and filtering', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.byTooltip('User options'));
    await tester.pumpAndSettle();
    expect(find.text('7 followers'), findsOneWidget);
    await tester.tap(find.text('Block'));
    await tester.pumpAndSettle();
    expect(find.text('Block user?'), findsOneWidget);
    await tester.tap(find.text('Block').last);
    await tester.pumpAndSettle();
    expect(blocks.calls, [('11', true)]);
    expect(find.text('Traveler 11'), findsNothing);
  });

  testWidgets('avatar/name route uses the actual user ID', (tester) async {
    await show(tester);
    await tester.tap(find.text('Traveler 11'));
    await tester.pumpAndSettle();
    expect(tester.widget<ProfileScreen>(find.byType(ProfileScreen)).userId, 11);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(follow.isClosed, isFalse);
    expect(block.isClosed, isFalse);
  });

  testWidgets(
    'pagination retains cards and uses page two with a compact footer',
    (tester) async {
      people.last = 2;
      await show(tester);
      final element = tester.element(find.byType(FollowUserTile));
      people.hold = true;
      await tester.tap(find.text('Load more'));
      await tester.pump();
      expect(people.reads.last.page, 2);
      expect(tester.element(find.byType(FollowUserTile)), same(element));
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      people.reads.last.result.complete(
        people.page(FollowListType.followers, 2),
      );
      await tester.pumpAndSettle();
      expect(find.text('Traveler 33'), findsOneWidget);
      expect(find.text('Traveler 11'), findsOneWidget);
    },
  );

  testWidgets(
    'refresh has one orange indicator, no native spinner and preserves cards',
    (tester) async {
      await show(tester);
      people.hold = true;
      final element = tester.element(find.byType(FollowUserTile));
      final refresh = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator),
      );
      final first = refresh.onRefresh();
      final second = refresh.onRefresh();
      await tester.pump();
      expect(people.reads, hasLength(2));
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(
        tester
            .widget<CupertinoActivityIndicator>(
              find.byType(CupertinoActivityIndicator),
            )
            .color,
        DarkColors.primaryColor,
      );
      expect(find.byType(RefreshProgressIndicator), findsNothing);
      expect(tester.element(find.byType(FollowUserTile)), same(element));
      people.reads.last.result.complete(
        people.page(FollowListType.followers, 1),
      );
      await first;
      await second;
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
    },
  );

  testWidgets(
    'failed refresh retains cards, stops indicator and permits retry',
    (tester) async {
      await show(tester);
      people.hold = true;
      final request = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pump();
      people.reads.last.result.completeError(
        ApiError(message: 'Network error'),
      );
      await request;
      await tester.pumpAndSettle();
      expect(find.text('Traveler 11'), findsOneWidget);
      expect(find.text('Network error'), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(find.byType(ProfileEmptyState), findsNothing);
    },
  );

  for (final type in [FollowListType.followers, FollowListType.following]) {
    testWidgets('$type empty state uses people artwork and correct CTA', (
      tester,
    ) async {
      people.empty = true;
      var explored = 0;
      await show(tester, type: type, explore: () => explored++);
      expect(svgAsset(tester), 'assets/images/profile/emptypic.svg');
      expect(
        find.text(
          type == FollowListType.followers
              ? 'No followers yet'
              : 'You don’t follow anyone yet.',
        ),
        findsOneWidget,
      );
      if (type == FollowListType.following) {
        await tester.tap(find.text('Explore People'));
        await tester.pumpAndSettle();
        expect(explored, 1);
      } else {
        expect(find.text('Explore People'), findsNothing);
      }
    });
  }

  testWidgets('loading and error states never show empty people artwork', (
    tester,
  ) async {
    people.hold = true;
    await show(tester, settle: false);
    expect(find.byType(ProfileEmptyState), findsNothing);
    people.reads.last.result.completeError(ApiError(message: 'Unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.byType(ProfileEmptyState), findsNothing);
  });

  testWidgets('long names and usernames do not overflow on small screens', (
    tester,
  ) async {
    people.long = true;
    await show(tester, width: 320, scale: 1.6);
    expect(tester.takeException(), isNull);
    final tile = tester.widget<PersonResultTile>(find.byType(PersonResultTile));
    expect(tile.user.name, contains('long traveler'));
  });

  testWidgets('session change rejects a pending people page', (tester) async {
    people.hold = true;
    final cubit = FollowUsersCubit(
      repo: people,
      userId: '7',
      type: FollowListType.followers,
    );
    final request = cubit.load();
    await PreferencesManager().clearSession();
    people.reads.single.result.complete(
      people.page(FollowListType.followers, 1),
    );
    await request;
    expect(cubit.state.users, isEmpty);
    expect(cubit.state.status, FollowUsersStatus.initial);
    await cubit.close();
  });

  testWidgets(
    'Profile Posts and Saved choose their SVGs only after successful loading',
    (tester) async {
      final profiles = MemoryProfileRepo();
      final posts = AuthorPostsRepo()
        ..authors[7] = []
        ..stored = [];
      var created = 0;
      await show(
        tester,
        child: ProfileScreen(
          profileRepo: profiles,
          postsRepo: posts,
          onCreatePost: () => created++,
        ),
      );
      expect(find.text('No posts yet'), findsOneWidget);
      expect(svgAsset(tester), 'assets/images/profile/emptypost.svg');
      await tester.ensureVisible(find.text('Create Post'));
      await tester.tap(find.text('Create Post'));
      await tester.pumpAndSettle();
      expect(created, 1);
      await tester.ensureVisible(find.text('Saved'));
      await tester.tap(find.text('Saved'));
      await tester.pumpAndSettle();
      expect(find.text('No saved items yet'), findsOneWidget);
      expect(svgAsset(tester), 'assets/images/profile/emptyitems.svg');
      expect(find.text('Create Post'), findsNothing);
    },
  );

  testWidgets(
    'Delete Account requires hidden password and red action, without unsupported feedback',
    (tester) async {
      final repo = deletion.MockAccountRepo();
      await show(tester, child: DeleteAccountScreen(repo: repo));
      expect(find.text('Current password *'), findsOneWidget);
      expect(find.text('Problem'), findsNothing);
      expect(find.text('0/24'), findsNothing);
      expect(find.byType(TextFormField), findsOneWidget);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).obscureText,
        isTrue,
      );
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).obscureText,
        isFalse,
      );
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Delete my Account'),
      );
      expect(
        button.style!.backgroundColor!.resolve({}),
        const Color(0xFFDB4A3D),
      );
      await tester.tap(find.text('Delete my Account'));
      await tester.pumpAndSettle();
      expect(find.text('Please enter your current password'), findsOneWidget);
      expect(repo.calls, 0);
    },
  );

  testWidgets(
    'Delete Account action stays above the keyboard on a small screen',
    (tester) async {
      final repo = deletion.MockAccountRepo();
      await show(
        tester,
        width: 320,
        height: 568,
        child: DeleteAccountScreen(repo: repo),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .getBottomRight(
              find.widgetWithText(ElevatedButton, 'Delete my Account'),
            )
            .dy,
        lessThanOrEqualTo(268),
      );
      expect(repo.calls, 0);
    },
  );

  testWidgets(
    'Explore People reuses the existing Buddies destination outside Root',
    (tester) async {
      people.empty = true;
      await show(tester, type: FollowListType.following);
      await tester.tap(find.text('Explore People'));
      await tester.pumpAndSettle();
      expect(find.byType(BuddiesScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(FollowUsersScreen), findsOneWidget);
    },
  );

  testWidgets(
    'a late old-session response cannot overwrite a new people page',
    (tester) async {
      people.hold = true;
      final cubit = FollowUsersCubit(
        repo: people,
        userId: '7',
        type: FollowListType.followers,
      );
      final oldRequest = cubit.load();
      final oldRead = people.reads.last;
      await PreferencesManager().saveToken('replacement-mock-session');
      final nextRead = people.reads.last;
      nextRead.result.complete(
        UsersPageModel(
          users: [person(22)],
          currentPage: 1,
          lastPage: 1,
          total: 1,
        ),
      );
      await cubit.pendingLoad;
      oldRead.result.complete(people.page(FollowListType.followers, 1));
      await oldRequest;
      expect(cubit.state.users.single.id, '22');
      await cubit.close();
    },
  );

  testWidgets(
    'glass logout is compact, clipped and cancel performs no request',
    (tester) async {
      final repo = LogoutRepo();
      await show(
        tester,
        child: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showLogOutDialogWidget(context, authRepo: repo),
              child: const Text('Open logout'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open logout'));
      await tester.pumpAndSettle();
      expect(find.text('Log Out?'), findsOneWidget);
      expect(find.text('Sign Out'), findsNothing);
      expect(find.byType(BackdropFilter), findsOneWidget);
      final glass = find.byKey(const ValueKey('logout-glass-surface'));
      expect(tester.getSize(glass).width, 320);
      final color =
          (tester.widget<DecoratedBox>(glass).decoration as BoxDecoration)
              .color!;
      expect(color.a, lessThan(1));
      expect(
        find.ancestor(
          of: find.byType(BackdropFilter),
          matching: find.byType(ClipRRect),
        ),
        findsWidgets,
      );
      expect(
        tester.getTopLeft(find.text('Log Out')).dx,
        lessThan(tester.getTopLeft(find.text('Cancel')).dx),
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.calls, 0);
    },
  );

  testWidgets('high contrast uses an opaque logout surface without blur', (
    tester,
  ) async {
    final repo = LogoutRepo();
    await show(
      tester,
      highContrast: true,
      width: 320,
      child: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showLogOutDialogWidget(context, authRepo: repo),
            child: const Text('Open logout'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open logout'));
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNothing);
    final color =
        (tester
                    .widget<DecoratedBox>(
                      find.byKey(const ValueKey('logout-glass-surface')),
                    )
                    .decoration
                as BoxDecoration)
            .color!;
    expect(color.a, 1);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}
