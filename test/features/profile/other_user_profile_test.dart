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
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/screens/conversation_screen.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_users_cubit.dart';
import 'package:travibe/features/search/data/users_page_model.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'package:travibe/features/profile/screens/profile_screen.dart';
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

void main() {
  late MemoryProfileRepo profiles;
  late Follows repo;
  late FollowCubit follow;
  late BlockCubit block;
  late Chats chats;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('profile-test');
    profiles = MemoryProfileRepo()
      ..result = ProfileModel.fromJson({
        ...profileJson(id: 23),
        'is_me': false,
        'follows_you': true,
        'is_following': false,
        'gender': 'female',
        'nationality': null,
        'nationality_code': 'EG',
      });
    repo = Follows();
    follow = FollowCubit(repo: repo);
    block = BlockCubit(follow: follow);
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
      expect(find.text('Remove Follower'), findsOneWidget);
      await tester.tap(find.text('Remove Follower'));
      await tester.pumpAndSettle();
      repo.removing = Completer<void>();
      await tester.tap(find.text('Remove'));
      await tester.pump();
      expect(repo.removed, ['23']);
      expect(follow.state.followsYou['23'], isNull);
      repo.removing!.complete();
      await tester.pumpAndSettle();
      expect(follow.state.followsYou['23'], false);
      expect(find.text('Follows You'), findsNothing);
      await tester.tap(find.byTooltip('Profile options'));
      await tester.pumpAndSettle();
      expect(find.text('Remove Follower'), findsNothing);
      expect(find.text('Share Profile'), findsOneWidget);
      expect(find.text('Report'), findsOneWidget);
      expect(find.text('Block User'), findsOneWidget);
    },
  );
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
    expect(find.text('Remove Follower'), findsNothing);
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
      expect(follow.state.following, isEmpty);
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
}
