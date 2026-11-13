import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/data/follow_errors.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';
import 'package:travibe/features/follow/widgets/follow_action_builder.dart';
import 'package:travibe/features/follow/widgets/follow_pill.dart';

class PrivateRepo extends FollowRepo {
  final calls = <bool>[];
  final results = <Completer<PublicUserModel>>[];
  FollowStatus? statusResult;
  @override
  Future<PublicUserModel> setFollowing(String id, bool following) {
    calls.add(following);
    final result = Completer<PublicUserModel>();
    results.add(result);
    return result.future;
  }

  @override
  Future<FollowStatus> status(String id) async =>
      statusResult ?? FollowStatus(userId: id, isFollowing: false);
}

PublicUserModel privateUser({bool following = false, bool requested = false}) =>
    PublicUserModel.fromJson({
      'id': 7,
      'name': 'Yasser',
      'is_private': true,
      'is_following': following,
      'follow_requested': requested,
    });

Widget pill(FollowCubit cubit, {bool initialRequested = false}) => MaterialApp(
  home: BlocProvider.value(
    value: cubit,
    child: Scaffold(
      body: Center(
        child: FollowActionBuilder(
          userId: '7',
          initialFollowing: false,
          initialRequested: initialRequested,
          builder: (context, relation, pending, onToggle) => FollowPill(
            relation: relation,
            pending: pending,
            onPressed: onToggle,
          ),
        ),
      ),
    ),
  ),
);

void main() {
  late PrivateRepo repo;
  late FollowCubit cubit;
  setUp(() {
    repo = PrivateRepo();
    cubit = FollowCubit(repo: repo);
  });
  tearDown(() => cubit.close());

  group('FollowCubit with private accounts', () {
    test(
      'following a private account becomes requested, not following',
      () async {
        final request = cubit.toggle('7', currentlyFollowing: false);
        repo.results.single.complete(privateUser(requested: true));
        await request;
        expect(repo.calls, [true]);
        expect(cubit.state.following['7'], isFalse);
        expect(cubit.state.requested['7'], isTrue);
        expect(cubit.state.relationOf('7'), FollowRelation.requested);
      },
    );

    test('toggling a pending request cancels it via unfollow', () async {
      final request = cubit.toggle(
        '7',
        currentlyFollowing: false,
        currentlyRequested: true,
      );
      expect(repo.calls, [false]);
      repo.results.single.complete(privateUser());
      await request;
      expect(cubit.state.requested['7'], isFalse);
      expect(cubit.state.relationOf('7'), FollowRelation.follow);
    });

    test('seeded request is shared and never overrides confirmed state', () {
      cubit.seed('7', requested: true);
      expect(
        cubit.state.relationOf('7', initialRequested: false),
        FollowRelation.requested,
      );
      cubit.seed('7', requested: false);
      expect(cubit.state.requested['7'], isTrue);
    });

    test('409 on follow reconciles from status and maps the message', () async {
      repo.statusResult = const FollowStatus(
        userId: '7',
        isFollowing: false,
        followRequested: true,
      );
      final request = cubit.toggle('7', currentlyFollowing: false);
      repo.results.single.completeError(
        ApiError(message: 'Conflict', statusCode: 409),
      );
      final error = await request;
      expect(error?.message, 'You already follow or requested this account.');
      expect(cubit.state.requested['7'], isTrue);
      expect(cubit.state.pending, isEmpty);
    });

    test('markFollowsYou records the accepted requester', () {
      cubit.markFollowsYou('9');
      expect(cubit.state.followsYou['9'], isTrue);
      expect(cubit.state.revision, 1);
    });
  });

  group('followError', () {
    test('maps conflicts by direction and blocks', () {
      expect(
        followError(
          ApiError(message: 'x', statusCode: 409),
          following: false,
        ).message,
        'This follow request was already handled.',
      );
      expect(
        followError(ApiError(message: 'x', statusCode: 409)).message,
        'This request was already handled.',
      );
      expect(
        followError(
          ApiError(
            message: 'You cannot follow a blocked user.',
            statusCode: 422,
          ),
          following: true,
        ).message,
        "You can't follow this account.",
      );
      expect(
        followError(ApiError(message: 'Other', statusCode: 500)).message,
        'Other',
      );
      expect(followError(Exception()).message, contains('Unable to update'));
    });
  });

  group('FollowActionBuilder Requested state', () {
    testWidgets('shows grey Requested and confirms before cancelling', (
      tester,
    ) async {
      await tester.pumpWidget(pill(cubit, initialRequested: true));
      final label = tester.widget<Text>(find.text('Requested'));
      expect(label.style?.color, requestedFollowColor);

      await tester.tap(find.text('Requested'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel follow request?'), findsOneWidget);
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      expect(repo.calls, isEmpty);
      expect(find.text('Requested'), findsOneWidget);

      await tester.tap(find.text('Requested'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel request'));
      await tester.pump();
      expect(repo.calls, [false]);
      repo.results.single.complete(privateUser());
      await tester.pumpAndSettle();
      expect(find.text('Follow'), findsOneWidget);
    });

    testWidgets('tapping Follow on a private account flips to Requested', (
      tester,
    ) async {
      await tester.pumpWidget(pill(cubit));
      await tester.tap(find.text('Follow'));
      await tester.pump();
      expect(find.text('Cancel follow request?'), findsNothing);
      repo.results.single.complete(privateUser(requested: true));
      await tester.pumpAndSettle();
      expect(find.text('Requested'), findsOneWidget);
    });
  });
}
