import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/widgets/glass_confirm_dialog.dart';
import 'package:travibe/core/widgets/more_options_button.dart';
import 'package:travibe/core/widgets/options_sheet.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/block/data/block_repo.dart';
import 'package:travibe/features/home/data/report_reason.dart';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/screens/conversation_screen.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_users_cubit.dart';
import 'package:travibe/features/search/data/users_page_model.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'package:travibe/features/profile/screens/profile_screen.dart';
import 'package:travibe/features/shares/data/post_share_actions.dart';
import '../chats/chat_fakes.dart';
import 'fixtures.dart';

class Follows extends FollowRepo {
  final removed = <String>[];
  final mutations = <bool>[];
  Completer<void>? removing;
  @override
  Future<void> removeFollower(String id) async {
    removed.add(id);
    await removing?.future;
  }

  @override
  Future<PublicUserModel> setFollowing(String id, bool following) async {
    mutations.add(following);
    return PublicUserModel.fromJson({
      'id': int.parse(id),
      'name': 'Traveler',
      'is_following': following,
    });
  }
}

class Blocks extends BlockRepo {
  final blocked = <String, bool>{};
  final calls = <bool>[];
  @override
  Future<BlockStatus> status(String userId) async =>
      BlockStatus(userId: userId, isBlocked: blocked[userId] ?? false);
  @override
  Future<PublicUserModel> setBlocked(String userId, bool value) async {
    calls.add(value);
    blocked[userId] = value;
    return PublicUserModel.fromJson({
      'id': int.parse(userId),
      'name': 'Traveler',
      'is_blocked': value,
    });
  }
}

class ReportingProfiles extends MemoryProfileRepo {
  final reports = <(String, String)>[];
  @override
  Future<void> reportUser(String userId, String reason) async =>
      reports.add((userId, reason));
}

class Chats extends FakeChatRepository {
  int creates = 0;
  Completer<ChatConversation>? _result;
  Completer<ChatConversation> get result =>
      _result ??= Completer<ChatConversation>();
  @override
  Future<ChatConversation> create(String id) {
    creates++;
    return result.future;
  }
}

const shareUrl = 'https://example.invalid/u/23';

void main() {
  late ReportingProfiles profiles;
  late Blocks blocks;
  late Follows repo;
  late FollowCubit follow;
  late BlockCubit block;
  late Chats chats;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('profile-test');
    profiles = ReportingProfiles()
      ..result = ProfileModel.fromJson({
        ...profileJson(id: 23),
        'is_me': false,
        'follows_you': true,
        'is_following': false,
        'url': shareUrl,
        'gender': 'female',
        'nationality': null,
        'nationality_code': 'EG',
      });
    repo = Follows();
    follow = FollowCubit(repo: repo);
    blocks = Blocks();
    block = BlockCubit(follow: follow, repo: blocks);
    chats = Chats();
  });
  tearDown(() async {
    await block.close();
    await follow.close();
  });
  Future<void> show(
    WidgetTester tester, {
    double width = 393,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: ThemeData.dark(),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: MultiBlocProvider(
                providers: [
                  BlocProvider.value(value: follow),
                  BlocProvider.value(value: block),
                ],
                child: ProfileScreen(
                  userId: 23,
                  profileRepo: profiles,
                  postsRepo: EmptyProfilePostsRepo(),
                  chatRepository: chats,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'public profile has authoritative relationship, action row and real About fields',
    (tester) async {
      await show(tester);
      expect(find.text('Follows You'), findsOneWidget);
      expect(find.text('Message'), findsOneWidget);
      expect(find.text('Follow'), findsOneWidget);
      await tester.tap(find.text('Follow'));
      await tester.pumpAndSettle();
      expect(repo.mutations, [true]);
      expect(find.widgetWithText(FilledButton, 'Following'), findsOneWidget);
      await tester.tap(find.text('About'));
      await tester.pumpAndSettle();
      expect(find.text('Gender'), findsOneWidget);
      expect(find.text('female'), findsOneWidget);
      expect(find.text('EG'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Photography'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Photography'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Posts').last,
        -150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Posts').last);
      await tester.pumpAndSettle();
      expect(find.text('No posts yet'), findsOneWidget);
    },
  );
  testWidgets(
    'remove follower is conditioned on follows_you and confirmed success hides it and badge',
    (tester) async {
      await show(tester);
      await tester.tap(find.byTooltip('Profile options'));
      await tester.pumpAndSettle();
      expect(find.text('Remove follower'), findsOneWidget);
      await tester.tap(find.text('Remove follower'));
      await tester.pumpAndSettle();
      repo.removing = Completer<void>();
      await tester.tap(find.text('Remove'));
      await tester.pump();
      expect(repo.removed, ['23']);
      // Seeded from the loaded profile; unchanged until the removal confirms.
      expect(follow.state.followsYou['23'], true);
      repo.removing!.complete();
      await tester.pumpAndSettle();
      expect(follow.state.followsYou['23'], false);
      expect(find.text('Follows You'), findsNothing);
      await tester.tap(find.byTooltip('Profile options'));
      await tester.pumpAndSettle();
      expect(find.text('Remove follower'), findsNothing);
      expect(find.text('Share profile'), findsOneWidget);
      expect(find.text('Report user'), findsOneWidget);
      expect(find.text('Block user'), findsOneWidget);
    },
  );
  group('profile share link', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      messenger.setMockMethodCallHandler(PostShareActions.channel, null);
    });

    testWidgets(
      'Share profile sends the backend url as-is to the native sheet',
      (tester) async {
        final calls = <MethodCall>[];
        messenger.setMockMethodCallHandler(PostShareActions.channel, (
          call,
        ) async {
          calls.add(call);
          return null;
        });
        await show(tester);
        await tester.tap(find.byTooltip('Profile options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Share profile'));
        await tester.pumpAndSettle();
        expect(calls.single.method, 'share');
        final args = calls.single.arguments as Map;
        expect(args['url'], shareUrl);
        expect(args.containsKey('text'), isFalse);
      },
    );

    testWidgets('Copy profile link copies the url and confirms', (
      tester,
    ) async {
      final copied = <Object?>[];
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add(call.arguments);
        return null;
      });
      await show(tester);
      await tester.tap(find.byTooltip('Profile options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy profile link'));
      await tester.pump();
      await tester.pump();
      expect(copied, [
        {'text': shareUrl},
      ]);
      expect(find.text('Link copied'), findsOneWidget);
    });

    testWidgets('a missing or invalid url hides Share and Copy', (
      tester,
    ) async {
      for (final url in [null, 'not a link', 'http://example.invalid/u/23']) {
        profiles.result = ProfileModel.fromJson({
          ...profileJson(id: 23),
          'is_me': false,
          'url': url,
        });
        await show(tester);
        await tester.tap(find.byTooltip('Profile options'));
        await tester.pumpAndSettle();
        expect(find.text('Share profile'), findsNothing, reason: '$url');
        expect(find.text('Copy profile link'), findsNothing, reason: '$url');
        expect(find.text('Report user'), findsOneWidget);
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      }
    });
  });

  testWidgets('Follows You badge is a grey chip with white text', (
    tester,
  ) async {
    await show(tester);
    final label = find.text('Follows You');
    final text = tester.widget<Text>(label);
    expect(text.style!.color, DarkColors.whiteColor);
    expect(text.style!.fontSize, 12);
    final box = tester.widget<DecoratedBox>(
      find.ancestor(of: label, matching: find.byType(DecoratedBox)).first,
    );
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.color, DarkColors.darkgreyColor);
    expect(decoration.borderRadius, BorderRadius.circular(8));
    final padding = tester.widget<Padding>(
      find.ancestor(of: label, matching: find.byType(Padding)).first,
    );
    expect(
      padding.padding,
      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    );
  });

  testWidgets('is_following alone never reveals Remove Follower', (
    tester,
  ) async {
    profiles.result = ProfileModel.fromJson({
      ...profileJson(id: 23),
      'is_me': false,
      'is_following': true,
      'follows_you': false,
    });
    await show(tester);
    expect(find.widgetWithText(FilledButton, 'Following'), findsOneWidget);
    expect(find.text('Follows You'), findsNothing);
    await tester.tap(find.byTooltip('Profile options'));
    await tester.pumpAndSettle();
    expect(find.text('Remove follower'), findsNothing);
  });
  testWidgets(
    'message opens returned existing conversation once with shared follow owner',
    (tester) async {
      await show(tester);
      await tester.tap(find.text('Message'));
      await tester.tap(find.text('Message'));
      await tester.pump();
      expect(chats.creates, 1);
      chats.result.complete(
        const ChatConversation(
          id: '44',
          participant: ChatParticipant(id: '23', name: 'Mona Hassan'),
          canSend: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ConversationScreen), findsOneWidget);
      final element = tester.element(find.byType(ConversationScreen));
      expect(element.read<FollowCubit>(), same(follow));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'late conversation response after switching accounts cannot navigate',
    (tester) async {
      await show(tester);
      await tester.tap(find.text('Message'));
      await tester.pump();
      await PreferencesManager().saveToken('different-profile-account');
      chats.result.complete(
        const ChatConversation(
          id: '44',
          participant: ChatParticipant(id: '23', name: 'Mona Hassan'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ConversationScreen), findsNothing);
      // Only the new account's own profile read; no carried-over mutation.
      expect(follow.state.following, {'23': false});
      expect(follow.state.revision, 0);
    },
  );
  for (final width in [320.0, 375.0, 393.0, 430.0]) {
    testWidgets(
      'public profile and options fit width $width at increased text scale',
      (tester) async {
        await show(tester, width: width, scale: 1.5);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Profile options'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
  test(
    'failed removal retains relationship; switching account drops late success',
    () async {
      repo.removing = Completer<void>();
      final operation = follow.removeFollower('23');
      repo.removing!.completeError(ApiError(message: 'Offline'));
      expect(await operation, isA<ApiError>());
      expect(follow.state.followsYou['23'], isNull);
      repo.removing = Completer<void>();
      final next = follow.removeFollower('23');
      await PreferencesManager().saveToken('new-account');
      repo.removing!.complete();
      await next;
      expect(follow.state.followsYou, isEmpty);
      expect(follow.state.pending, isEmpty);
    },
  );
  test(
    'forced relationship refresh rejects a page started before removal',
    () async {
      final first = Completer<UsersPageModel>();
      final second = Completer<UsersPageModel>();
      var requests = 0;
      final list = FollowUsersCubit(
        loadPage: (_) => requests++ == 0 ? first.future : second.future,
      );
      final old = list.load();
      final fresh = list.load(force: true);
      second.complete(
        const UsersPageModel(users: [], currentPage: 1, lastPage: 1, total: 0),
      );
      await fresh;
      first.complete(
        UsersPageModel(
          users: [
            PublicUserModel.fromJson({'id': 23, 'name': 'Removed'}),
          ],
          currentPage: 1,
          lastPage: 1,
          total: 1,
        ),
      );
      await old;
      expect(list.state.users, isEmpty);
      expect(list.state.total, 0);
      await list.close();
    },
  );

  testWidgets(
    'shared public profile navigation coalesces repeated entry taps',
    (tester) async {
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            theme: ThemeData.dark(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () {
                    unawaited(
                      ProfileScreen.open(
                        context,
                        userId: 23,
                        profileRepo: profiles,
                        postsRepo: EmptyProfilePostsRepo(),
                      ),
                    );
                    unawaited(
                      ProfileScreen.open(
                        context,
                        userId: 23,
                        profileRepo: profiles,
                        postsRepo: EmptyProfilePostsRepo(),
                      ),
                    );
                  },
                  child: const Text('Open profile'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open profile'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(profiles.reads.length, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  group('profile ⋮ menu', () {
    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Profile options'));
      await tester.pumpAndSettle();
    }

    Color? labelColor(WidgetTester tester, String label) =>
        tester.widget<Text>(find.text(label)).style?.color;

    testWidgets('⋮ opens the post-menu style sheet with profile rows', (
      tester,
    ) async {
      await show(tester);
      expect(find.byIcon(Icons.more_horiz), findsNothing);
      // Same circular-bordered ⋮ widget as the post card.
      final more = find.byType(MoreOptionsButton);
      expect(more, findsOneWidget);
      expect(
        find.descendant(of: more, matching: find.byIcon(Icons.more_vert)),
        findsOneWidget,
      );
      final box = tester.widget<Container>(
        find.descendant(of: more, matching: find.byType(Container)),
      );
      final decoration = box.decoration! as BoxDecoration;
      expect(
        (decoration.border! as Border).top.color,
        MoreOptionsButton.borderColor,
      );
      expect(decoration.color, isNull);
      expect(tester.getSize(more), const Size(38, 38));
      await openMenu(tester);
      final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
      expect(sheet.backgroundColor, optionsSheetColor);
      final radius =
          ((sheet.shape! as RoundedRectangleBorder).borderRadius
                  as BorderRadius)
              .topLeft
              .x;
      expect(radius, closeTo(24, 24 * .15));
      expect(find.byType(OptionSheetTile), findsNWidgets(5));
      final labels = [
        'Share profile',
        'Copy profile link',
        'Remove follower',
        'Report user',
        'Block user',
      ];
      final tops = [
        for (final label in labels) tester.getTopLeft(find.text(label)).dy,
      ];
      expect(tops, [...tops]..sort());
      expect(labelColor(tester, 'Remove follower'), DarkColors.whiteColor);
      final removeIcon = tester.widget<SvgPicture>(
        find.descendant(
          of: find.byKey(const ValueKey('profile-option-removeFollower')),
          matching: find.byType(SvgPicture),
        ),
      );
      expect(
        (removeIcon.bytesLoader as SvgAssetLoader).assetName,
        'assets/images/icons/user-remove.svg',
      );
      expect(
        removeIcon.colorFilter,
        const ColorFilter.mode(DarkColors.whiteColor, BlendMode.srcIn),
      );
      expect(labelColor(tester, 'Block user'), DarkColors.dangerColor);
      expect(labelColor(tester, 'Share profile'), DarkColors.whiteColor);
      expect(labelColor(tester, 'Report user'), DarkColors.whiteColor);
      final linkIcon = tester.widget<SvgPicture>(
        find.descendant(
          of: find.byKey(const ValueKey('profile-option-copyLink')),
          matching: find.byType(SvgPicture),
        ),
      );
      expect(
        (linkIcon.bytesLoader as SvgAssetLoader).assetName,
        'assets/images/icons/link-2.svg',
      );
      expect(find.text('Unblock user'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Block user confirms with the glass dialog before blocking', (
      tester,
    ) async {
      await show(tester);
      await openMenu(tester);
      await tester.tap(find.text('Block user'));
      await tester.pumpAndSettle();
      expect(find.byType(GlassConfirmDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(blocks.calls, isEmpty);

      await openMenu(tester);
      await tester.tap(find.text('Block user'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(GlassConfirmDialog),
          matching: find.text('Block'),
        ),
      );
      await tester.pumpAndSettle();
      expect(blocks.calls, [true]);
      expect(block.state.isBlocked('23'), isTrue);
      expect(find.text('This profile is unavailable.'), findsOneWidget);
    });

    testWidgets('a blocked profile keeps ⋮ with only Unblock user', (
      tester,
    ) async {
      blocks.blocked['23'] = true;
      await block.setBlocked('23', true);
      blocks.calls.clear();
      await show(tester);
      expect(find.text('This profile is unavailable.'), findsOneWidget);
      await openMenu(tester);
      expect(find.byType(OptionSheetTile), findsOneWidget);
      expect(find.text('Unblock user'), findsOneWidget);
      expect(labelColor(tester, 'Unblock user'), DarkColors.whiteColor);
      expect(find.text('Block user'), findsNothing);
      expect(find.text('Report user'), findsNothing);
      await tester.tap(find.text('Unblock user'));
      await tester.pumpAndSettle();
      expect(find.byType(GlassConfirmDialog), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(GlassConfirmDialog),
          matching: find.text('Unblock'),
        ),
      );
      await tester.pumpAndSettle();
      expect(blocks.calls, [false]);
      expect(block.state.isBlocked('23'), isFalse);
      expect(find.text('This profile is unavailable.'), findsNothing);
      await openMenu(tester);
      expect(find.text('Block user'), findsOneWidget);
    });

    testWidgets('Remove follower uses the glass confirm dialog', (
      tester,
    ) async {
      await show(tester);
      await openMenu(tester);
      await tester.tap(find.text('Remove follower'));
      await tester.pumpAndSettle();
      expect(find.byType(GlassConfirmDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.removed, isEmpty);
    });

    testWidgets('Report user opens the post report reasons sheet', (
      tester,
    ) async {
      await show(tester);
      await openMenu(tester);
      await tester.tap(find.text('Report user'));
      await tester.pumpAndSettle();
      expect(find.text(ReportReason.harassment.label), findsOneWidget);
      await tester.tap(find.text(ReportReason.harassment.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit Report'));
      await tester.pumpAndSettle();
      expect(profiles.reports, [('23', 'harassment')]);
      expect(find.text('Report submitted.'), findsOneWidget);
    });
  });
}
