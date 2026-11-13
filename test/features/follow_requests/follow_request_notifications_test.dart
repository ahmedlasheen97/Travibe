import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow_requests/cubit/incoming_requests_cubit.dart';
import 'package:travibe/features/notifications/data/notification_model.dart';
import 'package:travibe/features/notifications/data/notification_presentation.dart';
import 'package:travibe/features/notifications/data/notification_targets.dart';
import 'package:travibe/features/notifications/screens/notifications_screen.dart';
import 'package:travibe/features/notifications/widgets/notification_row.dart';

import '../notifications/notifications_screen_test.dart' show InboxRepo, app;
import 'follow_requests_fakes.dart';

Map<String, dynamic> followNotification(String type, {int actor = 3}) => {
  'id': '$type-$actor',
  'type': type,
  'actor': {
    'id': actor,
    'name': 'Omar',
    'username': 'omar',
    'is_following': false,
    'is_blocked': false,
  },
  'target_type': 'user',
  'target_id': actor,
  'data': <String, dynamic>{},
  'read_at': '2026-11-13T09:00:00Z',
  'created_at': '2026-11-13T09:00:00Z',
};

void main() {
  const resolver = NotificationPresentationResolver();
  setUp(() async {
    SharedPreferences.setMockInitialValues({'_token': 'auth'});
    await PreferencesManager().init();
  });
  tearDown(() => PreferencesManager().clear());

  test('follow request types have text and targets', () {
    final requested = InboxNotification.fromJson(
      followNotification('follow_requested'),
    );
    final accepted = InboxNotification.fromJson(
      followNotification('follow_request_accepted'),
    );
    expect(resolver.description(requested), 'requested to follow you');
    expect(resolver.description(accepted), 'accepted your follow request');
    expect(resolver.kind(requested), NotificationKind.follow);
    expect(resolver.secondary(requested), isNull);
    expect(
      NotificationTarget.from(requested)?.kind,
      NotificationTargetKind.followRequests,
    );
    final profile = NotificationTarget.from(accepted)!;
    expect(profile.kind, NotificationTargetKind.profile);
    expect(profile.id, 3);
  });

  testWidgets('pending request rows offer inline Accept/decline', (
    tester,
  ) async {
    final follow = FollowCubit();
    addTearDown(follow.close);
    final requests = FakeFollowRequestsRepo(
      pages: {
        1: requestsPage([3]),
      },
    );
    final incoming = IncomingRequestsCubit(repo: requests, follow: follow);
    addTearDown(incoming.close);
    final inbox = InboxRepo()
      ..items = [
        followNotification('follow_requested'),
        followNotification('follow_requested', actor: 5),
        followNotification('follow_request_accepted', actor: 6),
      ];
    final opened = <NotificationTargetKind>[];
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: follow),
          BlocProvider.value(value: incoming),
        ],
        child: app(
          NotificationsScreen(
            repo: inbox,
            openDestination: (_, _, content) async =>
                opened.add(content.target.kind),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('requested to follow you', findRichText: true),
      findsNWidgets(2),
    );
    expect(
      find.textContaining('accepted your follow request', findRichText: true),
      findsOneWidget,
    );
    // Only actor 3 still has a pending request; accepted rows show no Follow.
    expect(find.byKey(const ValueKey('accept-request-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('accept-request-5')), findsNothing);
    expect(find.text('Follow'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('accept-request-3')));
    await tester.pumpAndSettle();
    expect(requests.accepted, ['3']);
    expect(find.byKey(const ValueKey('accept-request-3')), findsNothing);

    await tester.tap(find.byType(NotificationRow).first);
    await tester.pumpAndSettle();
    expect(opened, [NotificationTargetKind.followRequests]);
  });
}
