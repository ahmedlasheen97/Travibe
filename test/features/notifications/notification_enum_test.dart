import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/notifications/data/notification_model.dart';
import 'package:travibe/features/notifications/data/notification_presentation.dart';
import 'package:travibe/features/notifications/screens/notifications_screen.dart';
import 'package:travibe/features/notifications/widgets/notification_row.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'notification_redesign_test.dart'
    show app, FollowFixture, NoNetworkCurrentUser;
import 'notifications_screen_test.dart' show InboxRepo;

const cases = <String, (NotificationKind, String?, String)>{
  'post_liked': (NotificationKind.like, 'liked.svg', 'liked your post'),
  'story_liked': (NotificationKind.like, 'liked.svg', 'liked your story'),
  'comment_liked': (NotificationKind.like, 'liked.svg', 'liked your comment'),
  'post_commented': (
    NotificationKind.comment,
    'comment.svg',
    'commented on your post',
  ),
  'comment_replied': (
    NotificationKind.comment,
    'comment.svg',
    'replied to your comment',
  ),
  'user_followed': (NotificationKind.follow, 'followedyou.svg', 'followed you'),
  'message_received': (
    NotificationKind.messageRequest,
    'messagerequest.svg',
    'sent you a message',
  ),
  'user_mentioned': (NotificationKind.unknown, null, 'mentioned you'),
};
InboxNotification notification(
  String type, {
  bool read = false,
  Map<String, dynamic>? actor = const {'id': 8, 'name': 'Actual actor'},
}) => InboxNotification.fromJson({
  'id': 'record',
  'type': type,
  'actor': actor,
  'data': {
    'body': 'Unverified preview and 99 others',
    'title': 'Unverified replacement actor',
  },
  'read_at': read ? '2026-11-07T00:00:00Z' : null,
  'created_at': '2026-11-06T23:00:00Z',
});
void main() {
  final prefs = PreferencesManager();
  const resolver = NotificationPresentationResolver();
  setUp(() async {
    SharedPreferences.setMockInitialValues({'_token': 'test-auth'});
    await prefs.init();
  });
  tearDown(() => prefs.clear());
  for (final entry in cases.entries) {
    testWidgets('${entry.key}: exact SVG, description and API actor', (
      tester,
    ) async {
      final item = notification(entry.key);
      final (kind, asset, message) = entry.value;
      expect(resolver.kind(item), kind);
      expect(resolver.description(item), message);
      await tester.pumpWidget(app(NotificationRow(item: item, onRead: () {})));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Actual actor $message', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Unverified', findRichText: true),
        findsNothing,
      );
      if (asset == null) {
        expect(find.byType(SvgPicture), findsNothing);
        expect(find.byIcon(Icons.notifications_none), findsOneWidget);
      } else {
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is SvgPicture &&
                w.bytesLoader is SvgAssetLoader &&
                (w.bytesLoader as SvgAssetLoader).assetName ==
                    'assets/images/notification/$asset',
          ),
          findsOneWidget,
        );
      }
      final text = tester.widget<Text>(
        find.byWidgetPredicate((w) => w is Text && w.textSpan != null).first,
      );
      expect(
        ((text.textSpan as TextSpan).children!.first as TextSpan)
            .style!
            .fontWeight,
        FontWeight.w600,
      );
      expect(
        find.byKey(const ValueKey('notification-unread-record')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
  test(
    'only the eight documented exact enum values are production aliases',
    () {
      expect(resolver.verifiedTypes.keys.toSet(), cases.keys.toSet());
      for (final type in [
        'POST_LIKED',
        'post_liked_extra',
        r'App\Enums\post_liked',
        'story_created',
        'nearby',
        'someone_in_your_city',
      ]) {
        final item = notification(type);
        expect(resolver.kind(item), NotificationKind.unknown);
        expect(resolver.description(item), 'New notification');
      }
    },
  );
  testWidgets(
    'unknown type ignores unverified data and retains neutral fallback',
    (tester) async {
      await tester.pumpWidget(
        app(NotificationRow(item: notification('unknown'), onRead: () {})),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Actual actor New notification',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('99 others', findRichText: true),
        findsNothing,
      );
    },
  );
  testWidgets(
    'missing actor renders confirmed description without a fabricated name',
    (tester) async {
      await tester.pumpWidget(
        app(
          NotificationRow(
            item: notification('message_received', actor: null),
            onRead: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('sent you a message', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Unverified replacement actor', findRichText: true),
        findsNothing,
      );
      expect(find.textContaining('null', findRichText: true), findsNothing);
    },
  );
  testWidgets(
    'read state does not alter confirmed kind/description or reserve a dot',
    (tester) async {
      final item = notification('post_liked', read: true);
      await tester.pumpWidget(app(NotificationRow(item: item, onRead: null)));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('notification-unread-record')),
        findsNothing,
      );
      expect(
        find.textContaining('liked your post', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('notification-icon-record')),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'confirmed user_followed enables the existing shared follow action',
    (tester) async {
      final repo = InboxRepo()
        ..items = [
          {
            'id': 'follow',
            'type': 'user_followed',
            'read_at': null,
            'actor': {
              'id': 8,
              'name': 'Actual actor',
              'is_following': false,
              'is_blocked': false,
            },
          },
        ];
      final followRepo = FollowFixture();
      final follow = FollowCubit(repo: followRepo);
      final user = NoNetworkCurrentUser()
        ..cacheProfile(
          const ProfileModel(id: '7'),
          expectedSession: prefs.sessionRevision,
        );
      await tester.pumpWidget(
        BlocProvider<CurrentUserCubit>.value(
          value: user,
          child: BlocProvider<FollowCubit>.value(
            value: follow,
            child: app(NotificationsScreen(repo: repo)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Actual actor followed you', findRichText: true),
        findsOneWidget,
      );
      await tester.tap(find.text('Follow'));
      await tester.pumpAndSettle();
      expect(find.text('Following'), findsOneWidget);
      expect(followRepo.calls, 1);
      expect(repo.items.single['read_at'], isNotNull);
      await tester.pumpWidget(const SizedBox());
      await follow.close();
      await user.close();
    },
  );
}
