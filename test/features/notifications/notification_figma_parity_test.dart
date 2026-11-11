import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/chats/screens/chats_screen.dart';
import 'package:travibe/features/notifications/cubit/notification_activity.dart';
import 'package:travibe/features/notifications/data/notification_model.dart';
import 'package:travibe/features/notifications/data/notification_presentation.dart';
import 'package:travibe/features/notifications/data/notification_targets.dart';
import 'package:travibe/features/notifications/screens/notification_navigation.dart';
import 'package:travibe/features/notifications/screens/notifications_screen.dart';
import 'package:travibe/features/notifications/widgets/notification_row.dart';
import '../chats/message_requests_test.dart' show RequestsRepo;
import '../profile/profile_posts_fixtures.dart' show authorPostJson;
import '../stories/story_viewer_test.dart' show viewerDetail;
import '../comments/fixtures.dart' show commentJson;
import 'notification_targets_flow_test.dart'
    show notice, TargetAdapter, ReadingRepo;
import 'notifications_screen_test.dart' show app;

const _post = 'https://cdn.fixtures.invalid/post.jpg';
const _story = 'https://cdn.fixtures.invalid/story.jpg';

Map<String, dynamic> _withPreview(
  Map<String, dynamic> json, {
  String? thumbnail,
  String? excerpt,
}) => {
  ...json,
  'preview': {'thumbnail_url': thumbnail, 'excerpt': excerpt},
};

InboxNotification _item(
  String type, {
  String? target,
  int? id = 10,
  Map<String, dynamic> data = const {},
  String? thumbnail,
  String? excerpt,
}) => InboxNotification.fromJson(
  _withPreview(
    notice(type, morph: target, target: id, data: data),
    thumbnail: thumbnail,
    excerpt: excerpt,
  ),
);

void main() {
  final preferences = PreferencesManager();
  const resolver = NotificationPresentationResolver();
  late TargetAdapter adapter;
  late NotificationTargetsRepository targets;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'_token': 'fixture-session'});
    await preferences.init();
    adapter = TargetAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://fixtures.invalid/api/v1/'))
      ..httpClientAdapter = adapter;
    targets = NotificationTargetsRepository(dio: dio, chats: RequestsRepo());
    adapter.values['posts/10'] = {
      'data': authorPostJson(10, 7)..['media'] = [],
    };
    adapter.values['stories/30'] = {'data': viewerDetail(30)};
    adapter.values['posts/10/comments/9'] = {
      'data': commentJson(9)..['post_id'] = 10,
    };
  });
  tearDown(() async {
    targets.dispose();
    await preferences.clear();
  });

  group('documented short target_type values', () {
    test('map to destinations; legacy morph names still work', () {
      NotificationTargetKind? kind(
        String type,
        String? target, {
        Map<String, dynamic> data = const {},
      }) => NotificationTarget.from(
        _item(type, target: target, data: data),
      )?.kind;
      expect(kind('post_liked', 'post'), NotificationTargetKind.post);
      expect(
        kind('post_liked', r'App\Models\Post'),
        NotificationTargetKind.post,
      );
      expect(kind('story_liked', 'story'), NotificationTargetKind.story);
      expect(
        kind('post_commented', 'comment', data: {'post_id': 10}),
        NotificationTargetKind.comment,
      );
      expect(kind('post_commented', 'post'), NotificationTargetKind.post);
      expect(
        kind('comment_replied', 'comment', data: {'post_id': 10}),
        NotificationTargetKind.comment,
      );
      // No post_id: unresolvable rather than guessed.
      expect(kind('comment_replied', 'comment'), isNull);
      expect(kind('user_followed', 'user'), NotificationTargetKind.profile);
      expect(
        kind('message_received', 'message', data: {'conversation_id': 4}),
        NotificationTargetKind.conversation,
      );
      expect(
        kind(
          'message_request_accepted',
          'message',
          data: {'conversation_id': 4},
        ),
        NotificationTargetKind.conversation,
      );
      expect(
        kind('buddy_nearby', null, data: const {}),
        NotificationTargetKind.buddies,
      );
    });
  });

  group('API preview presentation', () {
    test(
      'story thumbnail is portrait, post is square, none without preview',
      () {
        expect(
          resolver
              .thumbnail(
                _item('story_liked', target: 'story', thumbnail: _story),
              )!
              .kind,
          NotificationMediaKind.story,
        );
        expect(
          resolver
              .thumbnail(_item('post_liked', target: 'post', thumbnail: _post))!
              .kind,
          NotificationMediaKind.post,
        );
        expect(
          resolver
              .thumbnail(
                _item('post_commented', target: 'comment', thumbnail: _post),
              )!
              .kind,
          NotificationMediaKind.post,
        );
        expect(resolver.thumbnail(_item('post_liked', target: 'post')), isNull);
        expect(
          resolver.thumbnail(
            _item('post_liked', thumbnail: 'https://user:pw@cdn.invalid/a.jpg'),
          ),
          isNull,
        );
        expect(
          InboxNotification.fromJson({
            ...notice('post_liked'),
            'preview': null,
          }).preview,
          isNull,
        );
      },
    );

    test('excerpts, requests, grouped and mutual counts', () {
      expect(
        resolver.description(
          _item('post_commented', excerpt: 'best day of my life'),
        ),
        'commented: best day of my life',
      );
      expect(
        resolver.description(_item('comment_replied', excerpt: 'agreed')),
        'replied to your comment: agreed',
      );
      expect(
        resolver.description(_item('post_commented')),
        'commented on your post',
      );
      expect(
        resolver.description(
          _item('message_received', data: {'is_request': true}),
        ),
        'sent you a message request',
      );
      expect(
        resolver.description(_item('story_liked', data: {'others_count': 8})),
        'and 8 others liked your story',
      );
      expect(resolver.description(_item('story_liked')), 'liked your story');
      // Text-only liked post shows its excerpt as the secondary line.
      expect(
        resolver.secondary(_item('post_liked', excerpt: 'Bali was everything')),
        'Bali was everything',
      );
      expect(
        resolver.secondary(
          _item('post_liked', excerpt: 'caption', thumbnail: _post),
        ),
        isNull,
      );
      expect(
        resolver.secondary(
          _item('user_followed', data: {'mutual_followers_count': 47}),
        ),
        '47 mutual followers',
      );
    });
  });

  group('row', () {
    testWidgets('unread dot only while read_at is null; grouped name is bold', (
      tester,
    ) async {
      final unread = _item('story_liked', data: {'others_count': 8});
      await tester.pumpWidget(
        app(
          Scaffold(
            body: NotificationRow(item: unread, onRead: () {}),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('notification-unread-n1')),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Fixture actor and 8 others liked your story',
          findRichText: true,
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(
        app(
          Scaffold(
            body: NotificationRow(
              item: InboxNotification.fromJson(
                notice('story_liked', read: true),
              ),
              onRead: () {},
            ),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('notification-unread-n1')),
        findsNothing,
      );
    });

    testWidgets('thumbnail tap is a row tap; avatar tap is separate', (
      tester,
    ) async {
      var row = 0, avatar = 0;
      await tester.pumpWidget(
        app(
          Scaffold(
            body: NotificationRow(
              item: _item('post_liked', target: 'post', thumbnail: _post),
              onRead: () => row++,
              onAvatarTap: () => avatar++,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('notification-post-preview')),
        warnIfMissed: false,
      );
      expect((row, avatar), (1, 0));
      await tester.tap(find.byKey(const ValueKey('notification-avatar-n1')));
      expect((row, avatar), (1, 1));
    });
  });

  group('inbox', () {
    Future<List<NotificationContent>> pumpInbox(
      WidgetTester tester,
      List<Map<String, dynamic>> items,
    ) async {
      final opened = <NotificationContent>[];
      final repo = ReadingRepo()..items = items;
      final activity = NotificationActivity(repo: repo);
      addTearDown(activity.dispose);
      await tester.pumpWidget(
        app(
          NotificationsScreen(
            repo: repo,
            activity: activity,
            targets: targets,
            openDestination: (context, item, content) async =>
                opened.add(content),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return opened;
    }

    testWidgets('renders API thumbnails without per-row lookups', (
      tester,
    ) async {
      await pumpInbox(tester, [
        _withPreview(
          notice('post_liked', id: 'p', morph: 'post', target: 10),
          thumbnail: _post,
        ),
        _withPreview(
          notice('story_liked', id: 's', morph: 'story', target: 30),
          thumbnail: _story,
        ),
        _withPreview(
          notice('post_liked', id: 't', morph: 'post', target: 11),
          excerpt: 'text only',
        ),
      ]);
      expect(
        find.byKey(const ValueKey('notification-post-preview')),
        findsOneWidget,
      );
      expect(
        tester.getSize(
          find.byKey(const ValueKey('notification-story-preview')),
        ),
        const Size(48, 72),
      );
      expect(find.text('text only'), findsOneWidget);
      expect(adapter.calls, isEmpty);
    });

    testWidgets('avatar opens the actor profile for any type', (tester) async {
      final opened = await pumpInbox(tester, [
        notice('post_liked', morph: 'post', target: 10),
      ]);
      await tester.tap(find.byKey(const ValueKey('notification-avatar-n1')));
      await tester.pumpAndSettle();
      expect(opened.single.target.kind, NotificationTargetKind.profile);
      expect(opened.single.target.id, 7);
      expect(adapter.calls, isEmpty);
    });

    testWidgets('comment notification resolves the comment and its post', (
      tester,
    ) async {
      final opened = await pumpInbox(tester, [
        notice(
          'post_commented',
          morph: 'comment',
          target: 9,
          data: {'post_id': 10},
        ),
      ]);
      await tester.tap(find.byKey(const ValueKey('notification-n1')));
      await tester.pumpAndSettle();
      expect(opened.single.comment!.id, 9);
      expect(opened.single.post!.id, '10');
    });

    testWidgets('deleted story shows a snackbar and keeps the inbox', (
      tester,
    ) async {
      final opened = await pumpInbox(tester, [
        notice('story_liked', morph: 'story', target: 30),
      ]);
      adapter.status = 404;
      await tester.tap(find.byKey(const ValueKey('notification-n1')));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      expect(find.textContaining('unavailable'), findsOneWidget);
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('unresolvable message request falls back to Requests tab', (
      tester,
    ) async {
      final opened = await pumpInbox(tester, [
        notice('message_received', data: {'is_request': true}),
      ]);
      await tester.tap(find.byKey(const ValueKey('notification-n1')));
      await tester.pumpAndSettle();
      expect(opened.single.target.kind, NotificationTargetKind.conversation);
      expect(opened.single.conversation, isNull);
    });

    testWidgets('Requests fallback opens ChatsScreen in requests mode', (
      tester,
    ) async {
      final item = InboxNotification.fromJson(
        notice('message_received', data: {'is_request': true}),
      );
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => openNotificationDestination(
                context,
                item,
                const NotificationContent(
                  NotificationTarget(NotificationTargetKind.conversation, 0),
                ),
                chats: RequestsRepo(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ChatsScreen>(find.byType(ChatsScreen)).requests,
        true,
      );
    });

    testWidgets('buddy_nearby opens the buddies destination', (tester) async {
      final opened = await pumpInbox(tester, [
        {...notice('buddy_nearby'), 'actor': null},
      ]);
      expect(
        find.textContaining(
          'Someone is currently in your city',
          findRichText: true,
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('notification-n1')));
      await tester.pumpAndSettle();
      expect(opened.single.target.kind, NotificationTargetKind.buddies);
    });

    testWidgets(
      'Follow pill: shown when not following, hidden when following',
      (tester) async {
        Map<String, dynamic> follow(String id, int actor, bool following) => {
          ...notice('user_followed', id: id),
          'actor': {
            'id': actor,
            'name': 'Actor $actor',
            'is_blocked': false,
            'is_following': following,
          },
        };
        await pumpInbox(tester, [
          follow('a', 21, false),
          follow('b', 22, true),
        ]);
        expect(find.text('Follow'), findsOneWidget);
        expect(find.text('Following'), findsNothing);
      },
    );
  });
}
