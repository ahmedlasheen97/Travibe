import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/chats/screens/conversation_screen.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';
import 'package:travibe/features/follow/widgets/follow_action_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/notifications/firebase_messaging_client.dart';
import 'package:travibe/core/notifications/push_notification_service.dart';
import 'package:travibe/core/notifications/push_notifications_host.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/profile/data/profile_repo.dart';
import 'package:travibe/features/profilesetup/cubit/profile_setup_cubit.dart';
import 'package:travibe/features/profilesetup/data/profile_setup_repo.dart';
import 'package:travibe/features/profilesetup/screens/profile_setup_screen.dart';
import 'package:travibe/root.dart';

import '../../features/notifications/notification_activity_test.dart'
    show ActivityRepo;
import '../../features/profilesetup/identity_photo_test.dart'
    show Photos, Upload;
import '../../features/profilesetup/profile_setup_skip_test.dart' show SkipApi;
import '../../features/chats/chat_fakes.dart';
import 'push_fakes.dart';

/// Builds the push scope the app shell provides, with a device whose
/// notification permission has never been asked.
class PushRig {
  PushRig() {
    client = FakeMessagingClient()..status = PushPermission.notDetermined;
    service = PushNotificationService(
      client: client,
      repository: FakePushRepository(),
    );
    coordinator = PushNotificationsCoordinator(
      service,
      repository: ActivityRepo(),
    );
  }
  late final FakeMessagingClient client;
  late final PushNotificationService service;
  late final PushNotificationsCoordinator coordinator;

  Widget wrap(Widget home) => ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (_, _) => PushNotificationsScope(
      coordinator: coordinator,
      child: MaterialApp(theme: darkTheme, home: home),
    ),
  );

  Future<void> dispose() async {
    coordinator.dispose();
    service.dispose();
    await client.close();
  }
}

final softAsk = find.byKey(const ValueKey('notification-soft-ask'));

/// Pretends the last soft ask was shown [ago].
Future<void> lastShown(Duration ago) => PreferencesManager().setString(
  'notification_soft_ask_last_shown',
  DateTime.now().toUtc().subtract(ago).toIso8601String(),
);

Future<void> notNow(WidgetTester tester) async {
  await tester.tap(find.text('Not Now'));
  await tester.pumpAndSettle();
  expect(softAsk, findsNothing);
}

void main() {
  late PushRig push;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('soft-ask');
    push = PushRig();
  });
  tearDown(() async {
    await push.dispose();
    await PreferencesManager().clear();
  });

  group('after profile setup', () {
    late SkipApi api;

    setUp(() => api = SkipApi()..completeOnTravelStyles = true);

    ProfileSetupCubit cubit() {
      final upload = Upload();
      final cubit = ProfileSetupCubit(
        repo: ProfileSetupRepo(apiService: api),
        profileRepo: ProfileRepo(apiService: api),
        avatarRepo: Photos(),
        mediaUpload: upload,
        initialStep: 2,
      );
      addTearDown(() async {
        if (!cubit.isClosed) await cubit.close();
        upload.close();
      });
      return cubit;
    }

    /// Finishes ("Continue to Home") or skips setup on its last step.
    Future<void> leaveSetup(WidgetTester tester, {required bool skip}) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final setup = cubit();
      await tester.pumpWidget(
        push.wrap(
          ProfileSetupScreen(createCubit: (_) => setup, initialStep: 2),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(skip ? 'Skip For Now' : 'Continue to Home'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileSetupScreen), findsNothing);
      expect(tester.widget<Root>(find.byType(Root)).afterProfileSetup, isTrue);
    }

    for (final skip in [false, true]) {
      final how = skip ? 'skipped' : 'finished';
      testWidgets('setup $how → soft ask once on Home', (tester) async {
        await leaveSetup(tester, skip: skip);
        expect(softAsk, findsOneWidget);
        expect(push.client.prompts, 0);
        await notNow(tester);

        // Setup again (e.g. another pass through it), even after the gap:
        // this trigger has already asked.
        await tester.pumpWidget(const SizedBox());
        await lastShown(const Duration(days: 30));
        await leaveSetup(tester, skip: skip);
        expect(softAsk, findsNothing);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('Turn On after setup shows the system prompt', (tester) async {
      await leaveSetup(tester, skip: true);
      push.client.status = PushPermission.authorized;
      await tester.tap(find.text('Turn On'));
      await tester.pumpAndSettle();
      expect(push.client.prompts, 1);
      expect(softAsk, findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('respects the 3-day gap', (tester) async {
      await lastShown(const Duration(days: 2));
      await leaveSetup(tester, skip: false);
      expect(softAsk, findsNothing);
      await tester.pumpWidget(const SizedBox());

      // The blocked trigger wasn't used up: once the gap passes it can ask.
      await lastShown(const Duration(days: 3, minutes: 1));
      await leaveSetup(tester, skip: false);
      expect(softAsk, findsOneWidget);
      await notNow(tester);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a normal app start never asks', (tester) async {
      await tester.pumpWidget(push.wrap(const Root()));
      await tester.pumpAndSettle();
      expect(tester.widget<Root>(find.byType(Root)).afterProfileSetup, false);
      expect(softAsk, findsNothing);
      expect(push.client.prompts, 0);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('after the first follow', () {
    late ToggleFollowRepo repo;
    late FollowCubit follows;

    setUp(() {
      repo = ToggleFollowRepo();
      follows = FollowCubit(repo: repo);
    });
    tearDown(() => follows.close());

    Future<void> pumpButton(
      WidgetTester tester, {
      bool followingFirst = false,
    }) => tester.pumpWidget(
      push.wrap(
        BlocProvider.value(
          value: follows,
          child: Scaffold(
            body: Column(
              children: [
                for (final id in ['7', '8'])
                  FollowActionBuilder(
                    userId: id,
                    initialFollowing: followingFirst && id == '7',
                    builder: (context, relation, pending, onToggle) =>
                        TextButton(
                          key: ValueKey('follow-$id'),
                          onPressed: onToggle,
                          child: Text(relation.label),
                        ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    Future<void> toggle(WidgetTester tester, String id) async {
      await tester.tap(find.byKey(ValueKey('follow-$id')));
      await tester.pumpAndSettle();
    }

    testWidgets('soft ask once, never on later follows or unfollows', (
      tester,
    ) async {
      await pumpButton(tester);
      await toggle(tester, '7');
      expect(repo.calls, ['7:true']);
      expect(softAsk, findsOneWidget);
      expect(push.client.prompts, 0);
      await notNow(tester);

      // Even after the gap, this trigger has already asked.
      await lastShown(const Duration(days: 30));
      await toggle(tester, '7'); // unfollow
      await toggle(tester, '7'); // follow again
      await toggle(tester, '8'); // follow someone else
      expect(repo.calls, ['7:true', '7:false', '7:true', '8:true']);
      expect(softAsk, findsNothing);
      expect(push.client.prompts, 0);
    });

    testWidgets('a failed follow does not ask', (tester) async {
      repo.failure = true;
      await pumpButton(tester);
      await toggle(tester, '7');
      expect(find.text('Cannot follow this user'), findsOneWidget);
      expect(softAsk, findsNothing);
    });

    testWidgets('an unfollow does not ask; the next follow does', (
      tester,
    ) async {
      await pumpButton(tester, followingFirst: true);
      await toggle(tester, '7');
      expect(repo.calls, ['7:false']);
      expect(softAsk, findsNothing);
      await toggle(tester, '7');
      expect(softAsk, findsOneWidget);
      await notNow(tester);
    });

    testWidgets('respects the 3-day gap', (tester) async {
      await lastShown(const Duration(days: 2, hours: 23));
      await pumpButton(tester);
      await toggle(tester, '7');
      expect(softAsk, findsNothing);

      // The blocked follow didn't use the trigger up.
      await lastShown(const Duration(days: 3, minutes: 1));
      await toggle(tester, '8');
      expect(softAsk, findsOneWidget);
      await notNow(tester);
    });

    testWidgets('Turn On shows the system prompt', (tester) async {
      await pumpButton(tester);
      await toggle(tester, '7');
      push.client.status = PushPermission.authorized;
      await tester.tap(find.text('Turn On'));
      await tester.pumpAndSettle();
      expect(push.client.prompts, 1);
    });
  });

  group('after the first sent chat message', () {
    late FakeChatRepository repo;

    setUp(() => repo = FakeChatRepository());

    Future<void> pumpChat(WidgetTester tester) async {
      await tester.pumpWidget(
        push.wrap(
          ConversationScreen(
            conversation: conversation,
            repository: repo,
            currentUserId: 'self',
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> send(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
    }

    testWidgets('soft ask once after the server confirms a send', (
      tester,
    ) async {
      await pumpChat(tester);
      expect(softAsk, findsNothing);
      await send(tester, 'Hello');
      expect(repo.sends, 1);
      expect(softAsk, findsOneWidget);
      expect(push.client.prompts, 0);
      await notNow(tester);

      // Even after the gap, this trigger has already asked.
      await lastShown(const Duration(days: 30));
      await send(tester, 'Second');
      expect(repo.sends, 2);
      expect(softAsk, findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a failed send does not ask', (tester) async {
      repo.failure = ApiError(message: 'Rejected', statusCode: 422);
      await pumpChat(tester);
      await send(tester, 'Hello');
      expect(repo.sends, 1);
      expect(softAsk, findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('respects the 3-day gap', (tester) async {
      await lastShown(const Duration(days: 1));
      await pumpChat(tester);
      await send(tester, 'Hello');
      expect(softAsk, findsNothing);

      await lastShown(const Duration(days: 4));
      await send(tester, 'Later');
      expect(softAsk, findsOneWidget);
      await notNow(tester);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('each trigger asks once, sharing one gap', (tester) async {
    final repo = ToggleFollowRepo();
    final follows = FollowCubit(repo: repo);
    addTearDown(follows.close);
    final chat = FakeChatRepository();
    await tester.pumpWidget(
      push.wrap(
        BlocProvider.value(
          value: follows,
          child: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  FollowActionBuilder(
                    userId: '7',
                    initialFollowing: false,
                    builder: (context, relation, pending, onToggle) =>
                        TextButton(
                          onPressed: onToggle,
                          child: Text(relation.label),
                        ),
                  ),
                  Expanded(
                    child: ConversationScreen(
                      conversation: conversation,
                      repository: chat,
                      currentUserId: 'self',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Follow'));
    await tester.pumpAndSettle();
    expect(softAsk, findsOneWidget);
    await notNow(tester);

    // The chat trigger is new, but the follow ask started the gap.
    await tester.enterText(find.byType(TextField), 'Hi');
    await tester.pump();
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(softAsk, findsNothing);

    // Once the gap passes, the first send still asks: it's its own trigger.
    await lastShown(const Duration(days: 4));
    await tester.enterText(find.byType(TextField), 'Again');
    await tester.pump();
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(softAsk, findsOneWidget);
    await notNow(tester);
    await tester.pumpWidget(const SizedBox());
  });
}

/// Follows/unfollows immediately; [failure] rejects like the backend does.
class ToggleFollowRepo extends FollowRepo {
  final calls = <String>[];
  bool failure = false;

  @override
  Future<PublicUserModel> setFollowing(String userId, bool following) async {
    calls.add('$userId:$following');
    if (failure) {
      throw ApiError(message: 'Cannot follow this user', statusCode: 422);
    }
    return PublicUserModel.fromJson({
      'id': int.parse(userId),
      'is_following': following,
    });
  }
}
