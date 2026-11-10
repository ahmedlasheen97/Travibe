import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:travibe/features/home/widgets/home_user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';
import 'package:travibe/features/notifications/data/notification_model.dart';
import 'package:travibe/features/notifications/data/notification_presentation.dart';
import 'package:travibe/features/notifications/screens/notifications_screen.dart';
import 'package:travibe/features/notifications/widgets/notification_row.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'notifications_screen_test.dart' show InboxRepo;
import 'notification_activity_test.dart' show ActivityRepo;

class VerifiedFixturePresentation extends NotificationPresentationResolver {
  const VerifiedFixturePresentation()
    : super(
        verifiedTypes: const {
          'fixture.like': NotificationKind.like,
          'fixture.comment': NotificationKind.comment,
          'fixture.follow': NotificationKind.follow,
          'fixture.message': NotificationKind.messageRequest,
          'fixture.nearby': NotificationKind.nearby,
        },
      );
  @override
  String description(InboxNotification item) =>
      item.description ?? super.description(item);
  @override
  NotificationThumbnail? thumbnail(InboxNotification item) => switch (item.id) {
    'post-image' => const NotificationThumbnail(
      url: 'https://fixtures.invalid/post.png',
      kind: NotificationMediaKind.post,
    ),
    'story-image' => const NotificationThumbnail(
      url: 'https://fixtures.invalid/story.png',
      kind: NotificationMediaKind.story,
    ),
    _ => null,
  };
}

class NoNetworkCurrentUser extends CurrentUserCubit {
  @override
  Future<void> load() async {}
}

class FollowFixture extends FollowRepo {
  int calls = 0;
  Completer<void>? gate;
  @override
  Future<PublicUserModel> setFollowing(String id, bool following) async {
    calls++;
    if (gate != null) await gate!.future;
    return PublicUserModel.fromJson({
      'id': int.parse(id),
      'name': 'Traveler',
      'is_following': following,
    });
  }
}

Map<String, dynamic> rowJson({
  String id = 'one',
  String type = 'fixture.like',
  bool read = false,
  int actor = 8,
  bool blocked = false,
}) => {
  'id': id,
  'type': type,
  'actor': {
    'id': actor,
    'name': 'A traveler',
    'avatar_url': null,
    'is_following': false,
    'is_blocked': blocked,
  },
  'data': {'body': 'liked an update shared with you'},
  'read_at': read ? '2026-11-06T10:00:00Z' : null,
  'created_at': '2026-11-06T09:00:00Z',
};
Widget app(Widget child) => ScreenUtilInit(
  designSize: const Size(390, 844),
  builder: (_, _) => MaterialApp(
    theme: darkTheme,
    home: Scaffold(body: SafeArea(child: child)),
  ),
);
void main() {
  final prefs = PreferencesManager();
  setUp(() async {
    SharedPreferences.setMockInitialValues({'_token': 'fixture-auth'});
    await prefs.init();
  });
  tearDown(() => prefs.clear());
  for (final kind in NotificationKind.values.where(
    (k) => k != NotificationKind.unknown,
  )) {
    testWidgets('$kind loads its original SVG asset', (tester) async {
      final types = {
        for (final entry
            in const VerifiedFixturePresentation().verifiedTypes.entries)
          entry.value: entry.key,
      };
      await tester.pumpWidget(
        app(
          NotificationRow(
            item: InboxNotification.fromJson(rowJson(type: types[kind]!)),
            resolver: const VerifiedFixturePresentation(),
            onRead: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final asset = NotificationPresentationResolver.icon(kind)!;
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is SvgPicture &&
              w.bytesLoader is SvgAssetLoader &&
              (w.bytesLoader as SvgAssetLoader).assetName == asset,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('unknown type is neutral, never rendered as raw enum text', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        NotificationRow(
          item: InboxNotification.fromJson({
            'id': 'unknown',
            'type': r'App\Notifications\UnverifiedSecretType',
            'data': {},
          }),
          onRead: () {},
        ),
      ),
    );
    expect(
      find.textContaining('UnverifiedSecretType', findRichText: true),
      findsNothing,
    );
    expect(
      find.textContaining('New notification', findRichText: true),
      findsOneWidget,
    );
    expect(find.byType(SvgPicture), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'unread gutter stays reserved and avatar overlay stays within row',
    (tester) async {
      Future<void> show(bool read) async {
        await tester.pumpWidget(
          app(
            NotificationRow(
              item: InboxNotification.fromJson(rowJson(read: read)),
              resolver: const VerifiedFixturePresentation(),
              onRead: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show(false);
      final first = tester.getTopLeft(find.byType(HomeUserAvatar));
      expect(
        find.byKey(const ValueKey('notification-unread-one')),
        findsOneWidget,
      );
      final icon = tester.getRect(
        find.byKey(const ValueKey('notification-icon-one')),
      );
      final avatar = tester.getRect(find.byType(HomeUserAvatar));
      expect(icon.right, closeTo(avatar.right, .01));
      expect(icon.bottom, closeTo(avatar.bottom, .01));
      await show(true);
      expect(
        find.byKey(const ValueKey('notification-unread-one')),
        findsNothing,
      );
      expect(tester.getTopLeft(find.byType(HomeUserAvatar)), first);
    },
  );
  for (final id in ['post-image', 'story-image', 'text-only']) {
    testWidgets('$id allocates only confirmed media geometry', (tester) async {
      await tester.pumpWidget(
        app(
          NotificationRow(
            item: InboxNotification.fromJson(rowJson(id: id)),
            resolver: const VerifiedFixturePresentation(),
            onRead: () {},
          ),
        ),
      );
      final post = find.byKey(const ValueKey('notification-post-preview')),
          story = find.byKey(const ValueKey('notification-story-preview'));
      if (id == 'text-only') {
        expect(post, findsNothing);
        expect(story, findsNothing);
        expect(find.byType(Image), findsNothing);
      } else {
        final size = tester.getSize(id == 'post-image' ? post : story);
        expect(
          id == 'post-image'
              ? size.width == size.height
              : size.height > size.width,
          isTrue,
        );
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  for (final width in [320.0, 375.0, 393.0, 430.0]) {
    testWidgets('flat rows wrap at $width with large Arabic and English text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(
          MediaQuery(
            data: MediaQueryData(
              size: Size(width, 844),
              textScaler: TextScaler.linear(1.6),
            ),
            child: ListView(
              children: [
                NotificationRow(
                  item: InboxNotification.fromJson({
                    ...rowJson(id: 'story-image'),
                    'data': {
                      'body':
                          'A long notification description 🌴 مرحباً بك في الرحلة ' *
                          8,
                    },
                  }),
                  resolver: const VerifiedFixturePresentation(),
                  onRead: () {},
                ),
                NotificationRow(
                  item: InboxNotification.fromJson({
                    'id': 'missing',
                    'type': 'unknown',
                    'actor': null,
                    'data': {},
                  }),
                  onRead: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'shared follow state hides own/blocked actors and prevents duplicate requests',
    (tester) async {
      final repo = InboxRepo()
        ..items = [
          rowJson(type: 'fixture.follow'),
          rowJson(id: 'own', type: 'fixture.follow', actor: 7),
          rowJson(
            id: 'blocked',
            type: 'fixture.follow',
            actor: 9,
            blocked: true,
          ),
        ];
      final followRepo = FollowFixture()..gate = Completer();
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
            child: app(
              NotificationsScreen(
                repo: repo,
                presentation: const VerifiedFixturePresentation(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Follow'), findsOneWidget);
      await tester.tap(find.text('Follow'));
      await tester.pump();
      expect(followRepo.calls, 1);
      followRepo.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Following'), findsOneWidget);
      expect(followRepo.calls, 1);
      follow.applyBlockStatus('8', true);
      await tester.pumpAndSettle();
      expect(find.text('Following'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await follow.close();
      await user.close();
    },
  );
  testWidgets('render reference-sized inbox artifact', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fonts = FontLoader('Plus Jakarta Sans')
      ..addFont(rootBundle.load('assets/fonts/PlusJakartaSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/PlusJakartaSans-SemiBold.ttf'));
    await fonts.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final repo = InboxRepo()
      ..items = [
        rowJson(type: 'fixture.like'),
        rowJson(id: 'two', type: 'fixture.comment', read: true),
        rowJson(id: 'three', type: 'fixture.message', read: true),
        rowJson(id: 'four', type: 'fixture.follow'),
        {
          'id': 'nearby',
          'type': 'fixture.nearby',
          'actor': null,
          'read_at': null,
          'data': {'body': 'A location notification provided by the server'},
        },
        rowJson(id: 'six', type: 'fixture.comment', read: true),
      ];
    final key = GlobalKey();
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: RepaintBoundary(
            key: key,
            child: NotificationsScreen(
              repo: repo,
              presentation: const VerifiedFixturePresentation(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '/private/tmp/travibe-notification-redesign.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('already-read rows do not repeat the read mutation', (
    tester,
  ) async {
    final repo = ActivityRepo();
    await tester.pumpWidget(app(NotificationsScreen(repo: repo)));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('notification-one'));
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(repo.writes, 1);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(repo.writes, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
