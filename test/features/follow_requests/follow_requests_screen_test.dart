import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/widgets/people_skeleton.dart';
import 'package:travibe/features/follow_requests/cubit/incoming_requests_cubit.dart';
import 'package:travibe/features/follow_requests/screens/follow_requests_screen.dart';
import 'package:travibe/features/search/data/users_page_model.dart';

import 'follow_requests_fakes.dart';

class GatedRequestsRepo extends FakeFollowRequestsRepo {
  GatedRequestsRepo({super.pages});
  final listGate = Completer<void>();
  @override
  Future<UsersPageModel> list({int page = 1, int perPage = 15}) async {
    await listGate.future;
    return super.list(page: page, perPage: perPage);
  }
}

void main() {
  late FollowCubit follow;
  late CountingCurrentUser current;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'_token': 'auth'});
    await PreferencesManager().init();
    follow = FollowCubit();
    current = CountingCurrentUser();
  });
  tearDown(() async {
    await follow.close();
    await current.close();
  });

  Future<IncomingRequestsCubit> show(
    WidgetTester tester,
    FakeFollowRequestsRepo repo, {
    void Function(BuildContext, int)? onOpen,
    bool settle = true,
  }) async {
    final incoming = IncomingRequestsCubit(
      repo: repo,
      follow: follow,
      currentUser: () => current,
    );
    addTearDown(incoming.close);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: follow),
              BlocProvider.value(value: incoming),
            ],
            child: FollowRequestsScreen(onOpenProfile: onOpen),
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
    return incoming;
  }

  testWidgets('skeleton while loading, then rows with Figma layout', (
    tester,
  ) async {
    final repo = GatedRequestsRepo(
      pages: {
        1: requestsPage([3, 4]),
      },
    );
    await show(tester, repo, settle: false);
    await tester.pump();
    expect(find.byType(PeopleSkeleton), findsOneWidget);
    expect(find.text('Follow Requests'), findsOneWidget);
    repo.listGate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(PeopleSkeleton), findsNothing);
    expect(find.text('User 3'), findsOneWidget);
    expect(find.text('@user3'), findsOneWidget);
    expect(find.text('Accept'), findsNWidgets(2));
    expect(find.byIcon(Icons.close), findsNWidgets(2));
    final back = find.byTooltip('Back');
    expect(tester.getSize(back), const Size(44, 44));
  });

  testWidgets('empty state', (tester) async {
    await show(tester, FakeFollowRequestsRepo());
    expect(find.text('No follow requests'), findsOneWidget);
  });

  testWidgets('long names and usernames ellipsize without overflow', (
    tester,
  ) async {
    final repo = FakeFollowRequestsRepo(
      pages: {
        1: UsersPageModel.fromJson({
          'data': [
            requesterJson(
              5,
              name: 'Omar Khalrrrrrrrrrrrrrrrrrrrrrrrrrrrrrresssssss',
              username: 'omarkhalerrrrrrrrrrrrrrrrrrrrrrrrrrd1s',
            ),
          ],
          'meta': {'current_page': 1, 'last_page': 1, 'total': 1},
        }),
      },
    );
    await show(tester, repo);
    expect(tester.takeException(), isNull);
    final name = tester.widget<Text>(find.textContaining('Omar Khal'));
    expect(name.overflow, TextOverflow.ellipsis);
    expect(name.maxLines, 1);
  });

  testWidgets('accept and decline remove rows immediately', (tester) async {
    final repo = FakeFollowRequestsRepo(
      pages: {
        1: requestsPage([3, 4]),
      },
    )..gate = Completer<void>();
    final incoming = await show(tester, repo);
    await tester.tap(find.byKey(const ValueKey('accept-request-3')));
    await tester.pump();
    expect(find.text('User 3'), findsNothing);
    expect(current.deltas, [1]);
    await tester.tap(find.byKey(const ValueKey('decline-request-4')));
    await tester.pump();
    expect(find.text('User 4'), findsNothing);
    expect(find.text('No follow requests'), findsOneWidget);
    repo.gate!.complete();
    await tester.pumpAndSettle();
    expect(repo.accepted, ['3']);
    expect(repo.declined, ['4']);
    expect(incoming.state.total, 0);
  });

  testWidgets('a failed decline restores the row and shows the error', (
    tester,
  ) async {
    final repo = FakeFollowRequestsRepo(
      pages: {
        1: requestsPage([3]),
      },
    )..declineError = ApiError(message: 'Try again later', statusCode: 500);
    await show(tester, repo);
    await tester.tap(find.byKey(const ValueKey('decline-request-3')));
    await tester.pumpAndSettle();
    expect(find.text('User 3'), findsOneWidget);
    expect(find.text('Try again later'), findsOneWidget);
  });

  testWidgets('loads the next page near the end', (tester) async {
    final repo = FakeFollowRequestsRepo(
      pages: {
        1: requestsPage(
          [for (var i = 1; i <= 15; i++) i],
          lastPage: 2,
          total: 16,
        ),
        2: requestsPage([16], page: 2, lastPage: 2, total: 16),
      },
    );
    final incoming = await show(tester, repo);
    expect(incoming.state.total, 16);
    await tester.scrollUntilVisible(find.text('User 16'), 300);
    expect(repo.listCalls.map((c) => c.$1), containsAllInOrder([1, 2]));
    expect(incoming.contains('16'), isTrue);
  });

  testWidgets('tapping a row opens their profile', (tester) async {
    final opened = <int>[];
    await show(
      tester,
      FakeFollowRequestsRepo(
        pages: {
          1: requestsPage([3]),
        },
      ),
      onOpen: (_, id) => opened.add(id),
    );
    await tester.tap(find.text('User 3'));
    await tester.pumpAndSettle();
    expect(opened, [3]);
  });
}
