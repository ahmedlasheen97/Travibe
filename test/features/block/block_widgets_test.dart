import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/screen_util.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/block/widgets/block_user_button.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';
import 'package:travibe/features/follow/widgets/follow_user_tile.dart';
import 'package:travibe/features/home/widgets/suggested_users_section.dart';
import 'package:travibe/features/search/data/users_page_model.dart';
import 'package:travibe/features/search/widgets/person_result_tile.dart';
import 'block_cubit_test.dart' as fixture;

class Suggestions extends FollowRepo {
  @override
  Future<UsersPageModel> users({
    required FollowListType type,
    String? userId,
    int page = 1,
    int perPage = 15,
  }) async => UsersPageModel(
    users: [
      PublicUserModel.fromJson({'id': 7, 'name': 'Sara'}),
    ],
    currentPage: 1,
    lastPage: 1,
    total: 1,
  );
}

void main() {
  testWidgets(
    'search row and suggestions share block state and follow controls',
    (tester) async {
      final api = fixture.Repo();
      final follow = FollowCubit(repo: Suggestions());
      final block = BlockCubit(repo: api, follow: follow);
      addTearDown(() async {
        await block.close();
        await follow.close();
      });
      final user = PublicUserModel.fromJson({'id': 7, 'name': 'Sara'});
      await tester.pumpWidget(
        withScreenUtil(
          MaterialApp(
            home: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: follow),
                BlocProvider.value(value: block),
              ],
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      FollowUserTile(user: user),
                      const SuggestedUsersSection(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PersonResultTile), findsNWidgets(2));
      final request = block.setBlocked('7', true);
      await tester.pump(); // pending block must not remove a suggestion
      expect(find.byType(PersonResultTile), findsNWidgets(2));
      api.calls.last.result.complete(fixture.user('7', true, following: false));
      await request;
      await tester.pumpAndSettle();
      expect(find.byType(PersonResultTile), findsOneWidget);
      expect(
        tester
            .widget<PersonResultTile>(find.byType(PersonResultTile))
            .onFollowTap,
        isNull,
      );
      await tester.tap(find.byTooltip('User options'));
      await tester.pumpAndSettle();
      expect(find.text('Unblock'), findsOneWidget);
      await tester.tapAt(const Offset(1, 1));
      await tester.pumpAndSettle();
      final unblock = block.setBlocked('7', false);
      api.calls.last.result.complete(
        fixture.user('7', false, following: false),
      );
      await unblock;
      await tester.pumpAndSettle();
      expect(find.byType(PersonResultTile), findsNWidgets(2));
      for (final tile in tester.widgetList<PersonResultTile>(
        find.byType(PersonResultTile),
      )) {
        expect(tile.onFollowTap, isNotNull);
      }
    },
  );
  testWidgets(
    'status failure displays backend message and does not send a mutation',
    (tester) async {
      final api = fixture.Repo();
      final follow = FollowCubit();
      final block = BlockCubit(repo: api, follow: follow);
      addTearDown(() async {
        await block.close();
        await follow.close();
      });
      await tester.pumpWidget(
        withScreenUtil(
          MaterialApp(
            home: BlocProvider.value(
              value: block,
              child: const Scaffold(body: BlockUserButton(userId: '7')),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Block'));
      await tester.pump();
      api.checks.single.completeError(
        ApiError(message: 'Unauthenticated', statusCode: 401),
      );
      await tester.pump();
      expect(find.text('Unauthenticated'), findsOneWidget);
      expect(api.calls, isEmpty);
    },
  );
}
